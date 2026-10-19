import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Tablo D (docs/bug-tables.md §D): çoklu monitörde sıralı yerler. Her test
/// bir satır. Örnek düzen: rol sırası 1. Dell, 2. LG, 3. Samsung; laptop
/// ekranı hep var. Pencereler:
/// - Safari: `LG · 1`, `Dell · 2`; laptop `Laptop · 1`
/// - Mail: `Dell · 3`; laptop `Laptop · 2`
/// - Notes: `Samsung · 2`; laptop yeri yok
/// - Music: monitör yeri yok; laptop `Laptop · 3`
@MainActor
final class MultiMonitorDesk {

    static let builtin = ScreenService.RawDisplay(
        uuid: "BUILTIN", name: "Laptop", isBuiltin: true,
        frame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
        visibleFrame: CGRect(x: 0, y: 0, width: 1710, height: 1074))

    static func external(_ uuid: String, _ name: String, x: CGFloat) -> ScreenService.RawDisplay {
        .init(uuid: uuid, name: name, isBuiltin: false,
              frame: CGRect(x: x, y: 1112, width: 1920, height: 1080),
              visibleFrame: CGRect(x: x, y: 1112, width: 1920, height: 1050))
    }

    final class Source { var list: [ScreenService.RawDisplay] = [] }

    static let rules = [
        Rule(id: "safari", appName: "Safari", bundleID: "com.apple.Safari", tokens: [],
             docked: Destination(screen: "external-2", desktop: 1),
             undocked: Destination(screen: "builtin", desktop: 1),
             dockedNext: [Destination(screen: "external", desktop: 2)]),
        Rule(id: "mail", appName: "Mail", bundleID: "com.apple.mail", tokens: [],
             docked: Destination(screen: "external", desktop: 3),
             undocked: Destination(screen: "builtin", desktop: 2)),
        Rule(id: "notes", appName: "Notes", bundleID: "com.apple.Notes", tokens: [],
             docked: Destination(screen: "external-3", desktop: 2)),
        Rule(id: "music", appName: "Music", bundleID: "com.apple.Music", tokens: [],
             undocked: Destination(screen: "builtin", desktop: 3)),
    ]

    let source = Source()
    let screens: ScreenService
    let store: Store
    private var sync: [Any] = []
    /// Ekran adı → masaüstü sayısı (yoksa 3).
    var desktopCounts = ["Samsung": 2]
    var monitors: [String: ScreenService.RawDisplay] = [
        "Dell": external("DELL", "Dell", x: 1710),
        "LG": external("LG", "LG", x: 3630),
        "Samsung": external("SAMSUNG", "Samsung", x: 5550),
    ]

    /// Üç monitör ilk kez soldan sağa bağlanır: roller Dell, LG, Samsung
    /// olarak öğrenilir.
    init(rules: [Rule] = MultiMonitorDesk.rules) {
        source.list = [Self.builtin, monitors["Dell"]!, monitors["LG"]!, monitors["Samsung"]!]
        let source = source
        screens = ScreenService(displays: { source.list })
        var document = Document()
        document.rules = rules
        store = Store(demo: document)
        sync = AppModel.syncDisplayRoles(store: store, screens: screens)
        store.connectedRoles = { [screens] in Set(screens.screens.map(\.id)).subtracting(screens.heldRoles) }
    }

    /// Yalnız bu monitörler bağlı (laptop hep); ekranlar hemen yatışır.
    func connect(_ names: [String]) {
        source.list = [Self.builtin] + names.map { monitors[$0]! }
        screens.simulateChangeForTesting(settle: true)
    }

    func uuid(_ name: String) -> String { monitors[name]!.uuid }

    var current: [(role: String, uuid: String)] {
        screens.connectedExternals.map { (role: $0.role, uuid: $0.display.uuid) }
    }

    func choose(_ name: String, for role: String) {
        store.chooseDisplay(uuid(name), for: role, current: current)
    }

    /// Bağlı monitörün rolü.
    func role(of name: String) -> String? {
        screens.screens.first { $0.uuid == uuid(name) }?.id
    }

    /// Pencerenin bu taramadaki yeri: "Dell · 2", "Laptop · 1"; dokunulmazsa nil.
    func place(_ id: String) -> String? {
        resolved(id).map { resolved in
            let screen = screens.screens.first { $0.id == resolved.destination.screen }
            let name = screen?.name ?? resolved.destination.screen
            let desktop = Router.desktopIndex(resolved.destination.desktop,
                                              count: desktopCounts[name] ?? 3)
            return "\(name) · \(desktop)"
        }
    }

    func resolved(_ id: String) -> Routing.ResolvedPlace? {
        guard let rule = store.document.rule(id) else { return nil }
        let places = rule.places(screens.mode)
        guard !places.isEmpty else { return nil }
        return Router.resolvePlaces(places, nameSpaces: [:], holdNames: false, displays: [],
                                    screens: screens.screens, heldRoles: screens.heldRoles)
    }

    func places(_ id: String) -> [String] {
        (store.document.rule(id)?.places(.docked) ?? []).map { "\($0.screen) · \($0.desktop)" }
    }
}

// MARK: - D1 · Tak ve çıkar

@MainActor
struct DockedPlacesPlugTests {

    @Test func d1_1_laptopOnly() {
        let desk = MultiMonitorDesk()
        desk.connect([])
        #expect(desk.place("safari") == "Laptop · 1")
        #expect(desk.place("mail") == "Laptop · 2")
        #expect(desk.place("music") == "Laptop · 3")
        #expect(desk.place("notes") == nil)
    }

    @Test func d1_2_plugDell() {
        let desk = MultiMonitorDesk()
        desk.connect([])
        desk.connect(["Dell"])
        #expect(desk.place("safari") == "Dell · 2")
        #expect(desk.place("mail") == "Dell · 3")
        #expect(desk.place("notes") == "Dell · 2")
        #expect(desk.resolved("notes")?.choice == .fallback)
        #expect(desk.place("music") == nil)
    }

    @Test func d1_3_plugLG() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell"])
        desk.connect(["Dell", "LG"])
        #expect(desk.place("safari") == "LG · 1")
        #expect(desk.place("mail") == "Dell · 3")
        #expect(desk.place("notes") == "Dell · 2")
    }

    @Test func d1_4_plugSamsung() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell", "LG"])
        desk.connect(["Dell", "LG", "Samsung"])
        #expect(desk.place("notes") == "Samsung · 2")
        #expect(desk.place("safari") == "LG · 1")
        #expect(desk.place("mail") == "Dell · 3")
    }

    @Test func d1_5_unplugLG() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell", "Samsung"])
        #expect(desk.place("safari") == "Dell · 2")
        #expect(desk.resolved("safari")?.choice == .place(1))
        #expect(desk.place("mail") == "Dell · 3")
        #expect(desk.place("notes") == "Samsung · 2")
    }

    @Test func d1_6_unplugDell() {
        let desk = MultiMonitorDesk()
        desk.connect(["LG"])
        #expect(desk.place("safari") == "LG · 1")
        #expect(desk.place("mail") == "LG · 3")
        #expect(desk.resolved("mail")?.choice == .fallback)
        #expect(desk.place("notes") == "LG · 2")
    }

    @Test func d1_7_replugDell() {
        let desk = MultiMonitorDesk()
        desk.connect(["LG"])
        desk.connect(["LG", "Dell"])
        #expect(desk.place("mail") == "Dell · 3")
        #expect(desk.place("safari") == "LG · 1")
    }

    @Test func d1_8_unplugAll() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell", "LG"])
        desk.connect([])
        #expect(desk.place("safari") == "Laptop · 1")
        #expect(desk.place("mail") == "Laptop · 2")
        #expect(desk.place("notes") == nil)
    }

    @Test func d1_9_rearrangeKeepsPlaces() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell", "LG"])
        desk.monitors["LG"] = MultiMonitorDesk.external("LG", "LG", x: -1920)
        desk.connect(["Dell", "LG"])
        #expect(desk.role(of: "LG") == "external-2")
        #expect(desk.place("safari") == "LG · 1")
        #expect(desk.place("mail") == "Dell · 3")
    }

    /// Yedekte masaüstü numarası listenin ilk yerinden; ekranda o numara
    /// yoksa son masaüstü.
    @Test func d1_10_onlySamsungUsesFirstPlaceNumberAndClamps() {
        let desk = MultiMonitorDesk()
        desk.connect(["Samsung"])
        #expect(desk.place("mail") == "Samsung · 2")
        #expect(desk.place("safari") == "Samsung · 1")
        #expect(desk.place("notes") == "Samsung · 2")
    }
}

// MARK: - D2 · Yeni monitör (K6)

@MainActor
struct DockedPlacesNewMonitorTests {

    private func deskWithBenQ() -> MultiMonitorDesk {
        let desk = MultiMonitorDesk()
        desk.monitors["BenQ"] = MultiMonitorDesk.external("BENQ", "BenQ", x: 3630)
        desk.connect(["Dell"])
        desk.connect(["Dell", "BenQ"])
        return desk
    }

    @Test func d2_1_unknownMonitorWaits() {
        let desk = deskWithBenQ()
        let role = desk.role(of: "BenQ")
        #expect(role != nil && desk.screens.heldRoles.contains(role!))
        #expect(desk.place("safari") == "Dell · 2")
        #expect(desk.place("mail") == "Dell · 3")
        #expect(desk.place("notes") == "Dell · 2")
    }

    @Test func d2_2_addToTheEnd() {
        let desk = deskWithBenQ()
        desk.choose("BenQ", for: "external-4")
        #expect(desk.role(of: "BenQ") == "external-4")
        #expect(desk.screens.heldRoles.isEmpty)
        #expect(desk.place("safari") == "Dell · 2")
        #expect(desk.place("notes") == "Dell · 2")
    }

    @Test func d2_3_takeLGsPlace() {
        let desk = deskWithBenQ()
        desk.choose("BenQ", for: "external-2")
        #expect(desk.role(of: "BenQ") == "external-2")
        #expect(desk.screens.heldRoles.isEmpty)
        #expect(desk.place("safari") == "BenQ · 1")
    }

    @Test func d2_4_onlyHeldMonitorTouchesNothing() {
        let desk = deskWithBenQ()
        desk.connect(["BenQ"])
        #expect(desk.screens.mode == .docked)
        #expect(!desk.screens.heldRoles.isEmpty)
        #expect(desk.place("safari") == nil)
        #expect(desk.place("mail") == nil)
        #expect(desk.place("notes") == nil)
        #expect(desk.place("music") == nil)
    }
}

// MARK: - D3 · Kart başlığından monitör seçmek (K5)

@MainActor
struct DockedPlacesChooseTests {

    @Test func d3_1_swapDellAndLG() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell", "LG"])
        let before = desk.store.document.rules
        desk.choose("LG", for: "external")
        #expect(desk.role(of: "LG") == "external")
        #expect(desk.role(of: "Dell") == "external-2")
        #expect(desk.place("mail") == "LG · 3")
        #expect(desk.place("safari") == "Dell · 1")
        #expect(desk.store.document.rules == before)
    }

    @Test func d3_2_swapBack() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell", "LG"])
        desk.choose("LG", for: "external")
        desk.choose("Dell", for: "external")
        #expect(desk.place("mail") == "Dell · 3")
        #expect(desk.place("safari") == "LG · 1")
    }

    @Test func d3_3_chooseOnDisconnectedCard() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell"])
        desk.choose("Samsung", for: "external-2")
        let roles = desk.store.document.displayRoles
        #expect(roles.role(of: "SAMSUNG") == "external-2")
        #expect(roles.role(of: "LG") == "external-3")
        #expect(desk.place("safari") == "Dell · 2")
        desk.connect(["Dell", "Samsung"])
        #expect(desk.place("safari") == "Samsung · 1")
    }

    @Test func d3_5_unplugDellAfterSwap() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell", "LG"])
        desk.choose("LG", for: "external")
        desk.connect(["LG"])
        #expect(desk.place("safari") == "LG · 2")
        #expect(desk.place("mail") == "LG · 3")
    }

    /// Masaüstü planı rolle gider (K5: yerin bütün düzeni).
    @Test func d3_planFollowsTheRole() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell", "LG"])
        desk.store.document.plans.set(["A", "B"], .docked, "external")
        desk.choose("LG", for: "external")
        #expect(desk.store.document.plans.entries(.docked, desk.role(of: "LG")!) == ["A", "B"])
    }
}

// MARK: - D4 · Sürükleme ve yan panel (K7)

@MainActor
struct DockedPlacesEditTests {

    @Test func d4_1_sameMonitorReplaces() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell", "LG"])
        desk.store.setDestination(Destination(screen: "external-2", desktop: 2), for: "safari", mode: .docked)
        #expect(desk.places("safari") == ["external-2 · 2", "external · 2"])
        #expect(desk.place("safari") == "LG · 2")
    }

    @Test func d4_2_otherMonitorGoesFirst() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell", "LG"])
        desk.store.setDestination(Destination(screen: "external", desktop: 3), for: "safari", mode: .docked)
        #expect(desk.places("safari") == ["external · 3", "external-2 · 1"])
        #expect(desk.place("safari") == "Dell · 3")
    }

    @Test func d4_3_dropOnDisconnectedCard() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell"])
        desk.store.setDestination(Destination(screen: "external-3", desktop: 1), for: "safari", mode: .docked)
        #expect(desk.places("safari") == ["external-3 · 1", "external-2 · 1", "external · 2"])
        #expect(desk.place("safari") == "Dell · 2")
    }

    @Test func d4_4_moveUp() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell"])
        desk.store.movePlace(from: 1, to: 0, for: "safari", mode: .docked)
        #expect(desk.places("safari") == ["external · 2", "external-2 · 1"])
        #expect(desk.place("safari") == "Dell · 2")
    }

    @Test func d4_5_removeFallsBack() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell"])
        desk.store.removePlace(at: 1, for: "safari", mode: .docked)
        #expect(desk.places("safari") == ["external-2 · 1"])
        #expect(desk.place("safari") == "Dell · 1")
        #expect(desk.resolved("safari")?.choice == .fallback)
    }

    @Test func d4_6_removeOnlyPlaceLeavesWindowAlone() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell"])
        desk.store.removePlace(at: 0, for: "mail", mode: .docked)
        #expect(desk.places("mail").isEmpty)
        #expect(desk.store.document.rule("mail")?.undocked != nil)
        #expect(desk.place("mail") == nil)
    }

    @Test func d4_7_laptopPlaceChanges() {
        let desk = MultiMonitorDesk()
        desk.connect([])
        desk.store.setDestination(Destination(screen: "builtin", desktop: 2), for: "music", mode: .undocked)
        #expect(desk.place("music") == "Laptop · 2")
        #expect(desk.places("music").isEmpty)
    }

    @Test func d4_8_firstMonitorPlaceKeepsLaptopPlace() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell"])
        desk.store.setDestination(Destination(screen: "external", desktop: 1), for: "music", mode: .docked)
        #expect(desk.places("music") == ["external · 1"])
        #expect(desk.place("music") == "Dell · 1")
        #expect(desk.store.document.rule("music")?.undocked == Destination(screen: "builtin", desktop: 3))
    }

    /// Yalnız Dell bağlıyken Dell içinde sürüklemek LG'nin önceliğini
    /// bozmaz: LG takılınca Safari yine LG'ye gider.
    @Test func d4_9_sameMonitorDragKeepsDisconnectedPriority() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell"])
        desk.store.setDestination(Destination(screen: "external", desktop: 3), for: "safari", mode: .docked)
        #expect(desk.places("safari") == ["external-2 · 1", "external · 3"])
        #expect(desk.place("safari") == "Dell · 3")
        desk.connect(["Dell", "LG"])
        #expect(desk.place("safari") == "LG · 1")
    }

    /// Yedekteyken (listede bağlı yer yok) bağlı monitöre bırakmak yeni yeri
    /// sona ekler: bağlı olmayan, daha öncelikli LG'nin önüne geçmez.
    @Test func d4_10_dropWhileOnFallbackGoesLast() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell"])
        desk.store.removePlace(at: 1, for: "safari", mode: .docked)
        #expect(desk.resolved("safari")?.choice == .fallback)
        desk.store.setDestination(Destination(screen: "external", desktop: 3), for: "safari", mode: .docked)
        #expect(desk.places("safari") == ["external-2 · 1", "external · 3"])
        #expect(desk.place("safari") == "Dell · 3")
    }

    /// Bu kurulumda pini kaldırmak bütün sıralı listeyi siler.
    @Test func unpinClearsTheWholeList() {
        let desk = MultiMonitorDesk()
        desk.store.unpin("safari", mode: .docked)
        #expect(desk.places("safari").isEmpty)
        #expect(desk.store.document.rule("safari")?.undocked != nil)
    }
}

// MARK: - D5 · Adlı masaüstü, profil, unutma

@MainActor
struct DockedPlacesNamesProfilesTests {

    private let reading = Destination(screen: "external-2", desktop: 1, nameID: "READING")
    private let dell2 = Destination(screen: "external", desktop: 2)

    @Test func d5_1_nameOnLG() {
        let resolved = Routing.resolvePlace([reading, dell2], connected: ["builtin", "external", "external-2"],
                                            held: []) { _ in ("external-2", 1) }
        #expect(resolved?.destination.screen == "external-2")
        #expect(resolved?.choice == .place(0))
    }

    @Test func d5_2_nameMovedToDell() {
        let resolved = Routing.resolvePlace([reading, dell2], connected: ["builtin", "external", "external-2"],
                                            held: []) { _ in ("external", 3) }
        #expect(resolved?.destination == Destination(screen: "external", desktop: 3, nameID: "READING"))
    }

    @Test func d5_3_nameOnUnpluggedLGGoesToTheNextPlace() {
        let resolved = Routing.resolvePlace([reading, dell2], connected: ["builtin", "external"],
                                            held: []) { _ in nil }
        #expect(resolved?.destination == dell2)
        #expect(resolved?.choice == .place(1))
        // Yalnız yerleşmemiş ad varsa yedeğe gidilmez: ad yerleşince oraya.
        #expect(Routing.resolvePlace([reading], connected: ["builtin", "external"], held: []) { _ in nil } == nil)
    }

    @Test func d5_4_profilesKeepTheirOwnLists() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell", "LG"])
        let first = desk.store.document.activeProfileID
        desk.store.addProfile(named: "B")
        desk.store.pin(MultiMonitorDesk.rules[0], destination: Destination(screen: "external", desktop: 1),
                       mode: .docked)
        #expect(desk.place("safari") == "Dell · 1")
        desk.store.switchProfile(to: first)
        #expect(desk.place("safari") == "LG · 1")
        #expect(desk.places("safari") == ["external-2 · 1", "external · 2"])
    }

    @Test func d5_5_forgetLGSkipsItsPlaces() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell", "LG"])
        desk.store.forgetDisplay(desk.uuid("LG"))
        #expect(desk.places("safari") == ["external-2 · 1", "external · 2"])
        #expect(desk.place("safari") == "Dell · 2")
    }

    @Test func d5_6_confirmLGAgain() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell", "LG"])
        desk.store.forgetDisplay(desk.uuid("LG"))
        desk.choose("LG", for: "external-2")
        #expect(desk.place("safari") == "LG · 1")
    }

    @Test func d5_7_duplicatedProfileKeepsTheOrder() {
        let desk = MultiMonitorDesk()
        let source = desk.store.document.activeProfileID
        let copy = desk.store.duplicateProfile(source, named: "Copy")
        let safari = copy?.rules.first { $0.appName == "Safari" }
        #expect(safari?.id != "safari")
        #expect(safari?.places(.docked) == MultiMonitorDesk.rules[0].places(.docked))
    }

    /// Masaüstü silme sıradaki yerleri de kaydırır; silinen ikincil yer
    /// hayalete gider, geri gelince yine ikincil olur.
    @Test func deletingADesktopShiftsAndRestoresSecondaryPlaces() {
        var document = Document()
        document.rules = [MultiMonitorDesk.rules[0]]
        _ = document.removePlanEntry(screen: "external", desktop: 1, mode: .docked)
        #expect(document.rule("safari")?.places(.docked)
                == [Destination(screen: "external-2", desktop: 1), Destination(screen: "external", desktop: 1)])
        let ghost = document.removePlanEntry(screen: "external", desktop: 1, mode: .docked)
        #expect(document.rule("safari")?.places(.docked) == [Destination(screen: "external-2", desktop: 1)])
        #expect(ghost?.pins.first?.order == 1)
        document.applyGhostPins(ghost?.pins ?? []) { $0.destination }
        #expect(document.rule("safari")?.places(.docked)
                == [Destination(screen: "external-2", desktop: 1), Destination(screen: "external", desktop: 1)])
    }

    /// İlk yerin masaüstü silinince sıradaki yer ilk olur.
    @Test func deletingThePrimaryPromotesTheNextPlace() {
        var document = Document()
        document.rules = [MultiMonitorDesk.rules[0]]
        _ = document.removePlanEntry(screen: "external-2", desktop: 1, mode: .docked)
        #expect(document.rule("safari")?.places(.docked) == [Destination(screen: "external", desktop: 2)])
    }
}

// MARK: - D6 · Kayıt ve eski sürüm

struct DockedPlacesFileTests {

    private let safari = MultiMonitorDesk.rules[0]

    @Test func d6_1_writesFirstPlaceAndTheRest() throws {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(safari)) as! [String: Any]
        let docked = object["docked"] as? [String: Any]
        #expect(docked?["screen"] as? String == "external-2")
        let next = object["dockedNext"] as? [[String: Any]]
        #expect(next?.count == 1)
        #expect(next?.first?["screen"] as? String == "external")
    }

    @Test func d6_2_oldFileIsASinglePlaceList() throws {
        let json = #"{"id":"r","appName":"Mail","bundleID":"m","tokens":[],"docked":{"screen":"external","desktop":3,"layout":{"x":0,"y":0,"w":1,"h":1}}}"#
        let rule = try JSONDecoder().decode(Rule.self, from: Data(json.utf8))
        #expect(rule.places(.docked) == [Destination(screen: "external", desktop: 3)])
        // Tek yerli kural alanı hiç yazmaz.
        let text = String(decoding: try JSONEncoder().encode(rule), as: UTF8.self)
        #expect(!text.contains("dockedNext"))
    }

    @Test func d6_3_oldVersionSeesTheFirstPlace() throws {
        struct OldRule: Decodable { var docked: Destination? }
        let old = try JSONDecoder().decode(OldRule.self, from: JSONEncoder().encode(safari))
        #expect(old.docked == Destination(screen: "external-2", desktop: 1))
    }

    @Test func d6_4_oldVersionDropsTheRest() throws {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(safari)) as! [String: Any]
        object["dockedNext"] = nil
        let rule = try JSONDecoder().decode(Rule.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(rule.places(.docked) == [Destination(screen: "external-2", desktop: 1)])
    }

    @Test func d6_5_documentRoundTripKeepsListsAndRoles() throws {
        var document = Document()
        document.rules = MultiMonitorDesk.rules
        document.displayRoles = DisplayRoles(remembered: ["external": ["DELL"], "external-2": ["LG"]])
        let back = try JSONDecoder().decode(Document.self, from: JSONEncoder().encode(document))
        #expect(back.rules == document.rules)
        #expect(back.displayRoles == document.displayRoles)
    }

    /// Bozuk bir sıradaki yer atlanır, kalanlar okunur.
    @Test func badNextPlaceIsSkipped() throws {
        let json = #"{"id":"r","appName":"S","bundleID":"s","tokens":[],"docked":{"screen":"external","desktop":1,"layout":{"x":0,"y":0,"w":1,"h":1}},"dockedNext":[{"screen":3},{"screen":"external-2","desktop":2,"layout":{"x":0,"y":0,"w":1,"h":1}}]}"#
        let rule = try JSONDecoder().decode(Rule.self, from: Data(json.utf8))
        #expect(rule.places(.docked).map(\.screen) == ["external", "external-2"])
    }
}

// MARK: - D7 · Durum dosyası

struct DockedPlacesStatusTests {

    @Test func d7_4_placeStatus() {
        let status = Router.placeStatus(choices: [1: .place(0), 2: .place(1), 3: .fallback],
                                        unplaced: [3, 4])
        #expect(status == [1: "1", 2: "2", 3: "fallback", 4: "untouched"])
    }
}

// MARK: - Arayüz kararları (MapPlaces, K6, K8, D3.4)

@MainActor
struct DockedPlacesMapTests {

    private let safari = MultiMonitorDesk.rules[0]
    private let notes = MultiMonitorDesk.rules[2]

    private func known(_ id: String, _ name: String, builtin: Bool = false) -> KnownScreen {
        KnownScreen(id: builtin ? "builtin" : id, name: name, aspect: 1.6)
    }

    /// K8: bağlı olmayan harici kartlar altta; öbür planda hepsi üstte.
    @Test func k8_awayCardsGoBelow() {
        let screens = [known("external", "Dell"), known("external-2", "LG"),
                       known("builtin", "Laptop", builtin: true)]
        let live = MapPlaces.cardRows(screens, connected: ["builtin", "external"], live: true)
        #expect(live.main.map(\.id) == ["external", "builtin"])
        #expect(live.away.map(\.id) == ["external-2"])
        let plan = MapPlaces.cardRows(screens, connected: ["builtin"], live: false)
        #expect(plan.away.isEmpty)
        #expect(plan.main.count == 3)
    }

    /// K8: soluk kartın masaüstü sayısı: plan → son görülen → 1; yeri olan
    /// pinler kadar.
    @Test func k8_awayDesktopCount() {
        #expect(MapPlaces.awayDesktopCount(planned: 4, lastSeen: 2, used: 1) == 4)
        #expect(MapPlaces.awayDesktopCount(planned: 0, lastSeen: 2, used: 1) == 2)
        #expect(MapPlaces.awayDesktopCount(planned: 0, lastSeen: nil, used: 0) == 1)
        #expect(MapPlaces.awayDesktopCount(planned: 0, lastSeen: 2, used: 3) == 3)
    }

    @Test func lastDesktopCountIsLearnedForConfirmedMonitorsAndRoundTrips() throws {
        var roles = DisplayRoles(remembered: ["external": ["DELL"], "external-2": ["LG"]])
        roles = roles.learningDesktopCounts(["external": 4, "external-2": 2, "external-3": 5],
                                            assignment: [("external", "DELL"), ("external-2", "LG"),
                                                         ("external-3", "BENQ")])
        #expect(roles.lastDesktopCount == ["DELL": 4, "LG": 2])   // BenQ onay bekliyor
        #expect(roles.lastDesktopCount(role: "external-2") == 2)
        let back = try JSONDecoder().decode(DisplayRoles.self, from: JSONEncoder().encode(roles))
        #expect(back == roles)
        let empty = String(decoding: try JSONEncoder().encode(DisplayRoles()), as: UTF8.self)
        #expect(!empty.contains("lastDesktopCount"))
    }

    /// Kazanan yer: canlı planda bağlı ilk yer ya da yedek, öbür planda ilk yer.
    @Test func winnerFollowsTheConnectedMonitors() {
        #expect(MapPlaces.winner(safari, mode: .docked, live: true, usable: ["builtin", "external"])?
            .destination == Destination(screen: "external", desktop: 2))
        #expect(MapPlaces.winner(safari, mode: .docked, live: false, usable: [])?
            .destination == Destination(screen: "external-2", desktop: 1))
        #expect(MapPlaces.winner(notes, mode: .docked, live: true, usable: ["builtin", "external"])?
            .choice == .fallback)
    }

    /// DesktopRow kapalı pin çipleri bütün yerleri görür: LG yokken Safari
    /// Dell · 2'de; LG'nin soluk kartında "1 · Safari" hayalet çipi.
    @Test func closedPinsAndGhostChipsUseEveryPlace() {
        let rules = [safari, notes]
        let usable: Set<String> = ["builtin", "external"]
        #expect(MapPlaces.pinned(rules, mode: .docked, live: true, usable: usable,
                                 screen: "external", desktop: 2).map(\.id) == ["safari", "notes"])
        #expect(MapPlaces.pinned(rules, mode: .docked, live: true, usable: usable,
                                 screen: "external-2", desktop: 1).isEmpty)
        let ghosts = MapPlaces.ghosts(rules, mode: .docked, live: true, usable: usable, connected: usable,
                                      screen: "external-2", desktop: 1)
        #expect(ghosts.map(\.label) == ["1 · Safari"])
        #expect(MapPlaces.ghosts(rules, mode: .docked, live: true, usable: usable, connected: usable,
                                 screen: "external-3", desktop: 2).map(\.label) == ["1 · Notes"])
        // Bağlı kartta hayalet çip yok.
        #expect(MapPlaces.ghosts(rules, mode: .docked, live: true, usable: usable, connected: usable,
                                 screen: "external", desktop: 2).isEmpty)
        // Öbür planda ilk yer normal çip, sonrakiler hayalet.
        #expect(MapPlaces.ghosts(rules, mode: .docked, live: false, usable: [], connected: [],
                                 screen: "external", desktop: 2).map(\.label) == ["2 · Safari"])
        // Takılı ama onay bekleyen monitörün kartında hayalet yok.
        #expect(MapPlaces.ghosts(rules, mode: .docked, live: true, usable: usable,
                                 connected: usable.union(["external-2"]),
                                 screen: "external-2", desktop: 1).isEmpty)
        // Laptop planında hayalet yok.
        #expect(MapPlaces.ghosts(rules, mode: .undocked, live: true, usable: ["builtin"], connected: ["builtin"],
                                 screen: "builtin", desktop: 1).isEmpty)
    }

    /// Yan panel: sıra, bağlı mı, kazanan mı; yedek notu.
    @Test func inspectorRows() {
        let both = MapPlaces.rows(safari, live: true, usable: ["builtin", "external", "external-2"])
        #expect(both.rows.map(\.wins) == [true, false])
        #expect(both.rows.map(\.connected) == [true, true])
        #expect(both.fallback == nil)
        let dell = MapPlaces.rows(safari, live: true, usable: ["builtin", "external"])
        #expect(dell.rows.map(\.wins) == [false, true])
        #expect(dell.rows.map(\.connected) == [false, true])
        let onlyLG = MapPlaces.rows(notes, live: true, usable: ["builtin", "external-2"])
        #expect(onlyLG.rows.map(\.wins) == [false])
        #expect(onlyLG.fallback?.destination.screen == "external-2")
        let plan = MapPlaces.rows(safari, live: false, usable: [])
        #expect(plan.rows.allSatisfy { !$0.wins && !$0.connected })
    }

    /// "Neden burada": listede kaçıncı yer ya da yedek.
    @Test func whyHereNamesThePlace() {
        let match = Routing.Match(destination: safari.docked!, ruleID: safari.id, rule: safari)
        let second = Routing.ResolvedPlace(destination: Destination(screen: "external", desktop: 2),
                                           choice: .place(1))
        let text = Routing.reason(for: match, screenName: "Dell", resolved: second) ?? ""
        #expect(text.contains(L("place %ld of %ld in its list", 2, 2)))
        #expect(text.contains(L("%@ · Desktop %ld", DisplayRoles.displayName(role: "external", name: "Dell"), 2)))
        let fallback = Routing.ResolvedPlace(destination: Destination(screen: "external", desktop: 1),
                                             choice: .fallback)
        #expect((Routing.reason(for: match, screenName: "Dell", resolved: fallback) ?? "")
            .contains(L("fallback: none of its monitors is connected")))
        // Tek yerli pin: ek yok.
        let mail = MultiMonitorDesk.rules[1]
        let plain = Routing.reason(for: Routing.Match(destination: mail.docked!, ruleID: mail.id, rule: mail),
                                   screenName: "Dell",
                                   resolved: Routing.ResolvedPlace(destination: mail.docked!, choice: .place(0)))
        #expect(!(plain ?? "").contains(" · " + L("place %ld of %ld in its list", 1, 1)))
    }

    /// Soluk kartlar monitör kimliğinden: onay bekleyen yeni monitör rolü
    /// geçici tutsa da rolün kalıcı sahibi kendi kartını alır.
    @Test func awayCardsComeFromMonitorsNotRoles() {
        let screens = [known("external", "BenQ"), known("external-2", "LG"),
                       known("builtin", "Laptop", builtin: true)]
        let roles = DisplayRoles(remembered: ["external": ["HOME"], "external-2": ["LG"]])
        // Yalnız onay bekleyen BenQ takılı, "external" rolünde.
        let connected: [(role: String, uuid: String)] = [("external", "BENQ")]
        let cards = MapPlaces.awayCards(known: screens, monitors: roles.knownMonitors(connected: connected),
                                        connectedUUIDs: ["BENQ"], connectedRoles: ["builtin", "external"],
                                        names: ["HOME": "Acme 27Q"])
        #expect(cards.map(\.id) == ["HOME", "LG"])
        #expect(cards[0].screen.name == "Acme 27Q")
        #expect(cards[0].sharesRole)
        #expect(!cards[1].sharesRole)
        // Hiçbir monitörü hatırlanmayan, takılı olmayan eski rol kartı da var.
        let legacy = MapPlaces.awayCards(known: [known("external-3", "Old")], monitors: [],
                                         connectedUUIDs: [], connectedRoles: ["builtin"], names: [:])
        #expect(legacy.map(\.id) == ["external-3"])
        // Takılı monitörün soluk kartı yok.
        let plugged = MapPlaces.awayCards(known: screens, monitors: roles.knownMonitors(connected: [("external", "HOME")]),
                                          connectedUUIDs: ["HOME"], connectedRoles: ["builtin", "external"],
                                          names: [:])
        #expect(plugged.map(\.id) == ["LG"])
    }

    @Test func monitorNamesAreLearnedForConfirmedMonitors() throws {
        let roles = DisplayRoles(remembered: ["external": ["DELL"]])
            .learningDesktopCounts(["external": 3, "external-2": 2],
                                   assignment: [("external", "DELL"), ("external-2", "BENQ")],
                                   names: ["DELL": "Dell U2723", "BENQ": "BenQ PD"])
        #expect(roles.monitorNames == ["DELL": "Dell U2723"])
        let back = try JSONDecoder().decode(DisplayRoles.self, from: JSONEncoder().encode(roles))
        #expect(back.monitorNames == roles.monitorNames)
    }

    /// K6 "Sıranın sonuna ekle": hatırlanmayan ve bağlı onaylı monitörün
    /// tutmadığı ilk rol.
    @Test func d2_2_addToTheEndRole() {
        let roles = DisplayRoles(remembered: ["external": ["DELL"], "external-2": ["LG"], "external-3": ["SAMSUNG"]])
        #expect(roles.nextFreeRole(connected: [("external", "DELL"), ("external-2", "BENQ")]) == "external-4")
        let gap = DisplayRoles(remembered: ["external": ["DELL"], "external-3": ["SAMSUNG"]])
        #expect(gap.nextFreeRole(connected: [("external", "DELL"), ("external-2", "BENQ")]) == "external-2")
    }

    /// D3.4/K9: kart menüsünde yalnız tanınan monitörler (bağlı onaylılar ve
    /// hatırlanan, bağlı olmayanlar); onay bekleyen yeni monitör yok.
    @Test func d3_4_menuListsOnlyKnownMonitors() {
        let roles = DisplayRoles(remembered: ["external": ["DELL"], "external-2": ["LG"], "external-3": ["SAMSUNG"]])
        let menu = roles.knownMonitors(connected: [("external", "DELL"), ("external-4", "BENQ")])
        #expect(menu.map(\.uuid) == ["DELL", "LG", "SAMSUNG"])
        #expect(menu.map(\.role) == ["external", "external-2", "external-3"])
    }
}
