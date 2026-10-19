import Combine
import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Harici ekran rolleri: konum sırasından kalıcı role, monitör sök/tak,
/// aynı model iki monitör, masa değişimi, elle seçim, eksik ekran yedeği.
/// Gerçek ikinci monitör gerekmez: ekran listesi sahte verilir.
struct DisplayRolesTests {

    private typealias Display = DisplayRoles.Display

    // Dell solda üstte, sanal ekran (Pebble) sağda; aynı model iki LG.
    private let dell = Display(uuid: "DELL-0001", minX: -1680, minY: 1112, name: "DELL U2720Q")
    private let pebble = Display(uuid: "PEBBLE-0002", minX: 1710, minY: 0, name: "Pebble")
    private let lgA = Display(uuid: "LG-A", minX: 0, minY: 1112, name: "LG HDR 4K")
    private let lgB = Display(uuid: "LG-B", minX: 2560, minY: 1112, name: "LG HDR 4K")

    private func roles(_ list: [Display], _ memory: DisplayRoles = DisplayRoles()) -> [String: String] {
        Dictionary(uniqueKeysWithValues: memory.assign(list).map { ($0.display.uuid, $0.role) })
    }

    private func learned(_ list: [Display], _ memory: DisplayRoles = DisplayRoles()) -> DisplayRoles {
        memory.learning(memory.assign(list).map { (role: $0.role, uuid: $0.display.uuid) })
    }

    /// Tek bağlı monitörü kullanıcı bir role verdi (kart menüsü).
    private func chosen(_ d: Display, _ role: String, _ memory: DisplayRoles) -> DisplayRoles {
        memory.choosing(d.uuid, for: role,
                        current: memory.assign([d]).map { (role: $0.role, uuid: $0.display.uuid) })
    }

    private func moved(_ d: Display, x: CGFloat) -> Display {
        Display(uuid: d.uuid, minX: x, minY: d.minY, name: d.name)
    }

    // MARK: Konum sırası (eski davranış)

    @Test func withoutMemoryRolesArePositionalLikeBefore() {
        #expect(roles([pebble, dell]) == ["DELL-0001": "external", "PEBBLE-0002": "external-2"])
        #expect(roles([lgB, lgA]) == ["LG-A": "external", "LG-B": "external-2"])
        #expect(roles([pebble]) == ["PEBBLE-0002": "external"])
        #expect(DisplayRoles().assign([]).isEmpty)
    }

    @Test func resultIsInRoleOrder() {
        let memory = learned([dell, pebble])
        let swapped = [moved(dell, x: 4000), moved(pebble, x: -2000)]
        #expect(memory.assign(swapped).map(\.role) == ["external", "external-2"])
    }

    // MARK: Kalıcı rol

    @Test func rearrangingDisplaysKeepsRoles() {
        let memory = learned([dell, pebble])
        // Kullanıcı Ekran ayarlarında sanal ekranı Dell'in soluna aldı.
        let rearranged = [moved(dell, x: 3000), moved(pebble, x: -1920)]
        #expect(roles(rearranged, memory) == ["DELL-0001": "external", "PEBBLE-0002": "external-2"])
    }

    @Test func virtualDisplayAddedOnTheLeftDoesNotStealTheFirstRole() {
        // Önce yalnız Dell bağlıydı, öğrenildi.
        let memory = learned([dell])
        let leftPebble = moved(pebble, x: -5000)
        #expect(roles([dell, leftPebble], memory) == ["DELL-0001": "external", "PEBBLE-0002": "external-2"])
    }

    @Test func unplugAndReplugInAnyOrderRestoresRoles() {
        var memory = learned([dell, pebble])
        // Dell çıkarıldı: Pebble tek başına kalır, rolü değişmez (external-2).
        #expect(roles([pebble], memory) == ["PEBBLE-0002": "external-2"])
        memory = learned([pebble], memory)
        // Dell geri geldi: yine external.
        #expect(roles([pebble, dell], memory) == ["DELL-0001": "external", "PEBBLE-0002": "external-2"])
    }

    @Test func secondMonitorAloneKeepsItsRoleSoRulesDoNotJump() {
        let memory = learned([dell, pebble])
        // Yalnız Pebble bağlıyken "external" boş kalır: Dell'in kuralları
        // Pebble'ya akmaz (eski konum sırasında Pebble external olurdu).
        #expect(memory.assign([pebble]).map(\.role) == ["external-2"])
    }

    // MARK: Masa değişimi (ofiste her masada başka monitör)

    /// Yeni monitör eksik rolün yerine oturur, ama rolü onay bekler
    /// (A4, docs/bug-tables.md): kendiliğinden öğrenilmez, seçilince hatırlanır.
    @Test func newMonitorTakesTheMissingRoleAndIsRemembered() {
        var memory = learned([dell])
        let desk = Display(uuid: "OFFICE-7", minX: 0, minY: 1112, name: "DELL U2720Q")
        #expect(roles([desk], memory) == ["OFFICE-7": "external"])
        #expect(learned([desk], memory) == memory)
        memory = chosen(desk, "external", memory)
        #expect(memory.remembered["external"] == ["OFFICE-7", "DELL-0001"])
        // Evde Dell yine external.
        #expect(roles([dell], memory) == ["DELL-0001": "external"])
    }

    @Test func twoRememberedForTheSameRoleMostRecentWins() {
        var memory = learned([dell])
        let desk = Display(uuid: "OFFICE-7", minX: 0, minY: 1112, name: "Other")
        memory = chosen(desk, "external", memory)  // external: [OFFICE-7, DELL]
        let both = roles([dell, desk], memory)
        #expect(both == ["OFFICE-7": "external", "DELL-0001": "external-2"])
    }

    @Test func historyIsCapped() {
        var memory = DisplayRoles()
        for i in 0..<12 {
            memory = chosen(Display(uuid: "D\(i)", minX: 0, minY: 0, name: "M"), "external", memory)
        }
        #expect(memory.remembered["external"]?.count == DisplayRoles.historyLimit)
        #expect(memory.remembered["external"]?.first == "D11")
    }

    // MARK: Aynı model iki monitör

    @Test func identicalModelsAreTellApartByUUIDAndKeepRolesWhenSwapped() {
        let memory = learned([lgA, lgB])
        #expect(roles([moved(lgA, x: 5000), moved(lgB, x: 0)], memory)
                == ["LG-A": "external", "LG-B": "external-2"])
    }

    @Test func identicalNamesGetLeftRightLabels() {
        let labels = DisplayRoles.labels([lgB, lgA, dell])
        #expect(labels["LG-A"] == "LG HDR 4K (left)")
        #expect(labels["LG-B"] == "LG HDR 4K (right)")
        #expect(labels["DELL-0001"] == "DELL U2720Q")
        let three = DisplayRoles.labels([lgA, lgB, Display(uuid: "LG-C", minX: 9000, minY: 0, name: "LG HDR 4K")])
        #expect(three["LG-C"] == "LG HDR 4K (3)")
    }

    @Test func duplicateUUIDIsCountedOnce() {
        let raw = [
            ScreenService.RawDisplay(uuid: "B", name: "Built-in", isBuiltin: true,
                                     frame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
                                     visibleFrame: CGRect(x: 0, y: 0, width: 1710, height: 1074)),
            ScreenService.RawDisplay(uuid: "X", name: "Mirror", isBuiltin: false,
                                     frame: CGRect(x: 1710, y: 0, width: 1920, height: 1080),
                                     visibleFrame: CGRect(x: 1710, y: 0, width: 1920, height: 1050)),
            ScreenService.RawDisplay(uuid: "X", name: "Mirror", isBuiltin: false,
                                     frame: CGRect(x: 1710, y: 0, width: 1920, height: 1080),
                                     visibleFrame: CGRect(x: 1710, y: 0, width: 1920, height: 1050)),
        ]
        #expect(ScreenService.detect(raw, roles: DisplayRoles()).map(\.id) == ["builtin", "external"])
    }

    // MARK: Elle seçim

    @Test func choosingTheOtherMonitorSwapsRoles() {
        let memory = learned([dell, pebble])
        let current = memory.assign([dell, pebble]).map { (role: $0.role, uuid: $0.display.uuid) }
        let chosen = memory.choosing("PEBBLE-0002", for: "external", current: current)
        #expect(roles([dell, pebble], chosen) == ["PEBBLE-0002": "external", "DELL-0001": "external-2"])
        // Kalıcı: yeniden düzenleme seçimi bozmaz.
        #expect(roles([moved(dell, x: -9000), pebble], chosen)
                == ["PEBBLE-0002": "external", "DELL-0001": "external-2"])
    }

    @Test func choosingTheSameMonitorChangesNothing() {
        let memory = learned([dell, pebble])
        let current = memory.assign([dell, pebble]).map { (role: $0.role, uuid: $0.display.uuid) }
        #expect(memory.choosing("DELL-0001", for: "external", current: current) == memory)
    }

    @Test func choosingAnEmptyHigherRoleMovesTheMonitor() {
        let memory = learned([dell, pebble])
        let current = memory.assign([dell, pebble]).map { (role: $0.role, uuid: $0.display.uuid) }
        let chosen = memory.choosing("DELL-0001", for: "external-3", current: current)
        // Pebble hatırladığı rolde kalır; Monitör 1 boşalır (arayüz bu yüzden
        // yalnız bağlı monitör sayısı kadar rol sunar, URL komutu da öyle).
        #expect(roles([dell, pebble], chosen) == ["PEBBLE-0002": "external-2", "DELL-0001": "external-3"])
    }

    @Test func choosingIgnoresNonExternalRoles() {
        let memory = learned([dell])
        #expect(memory.choosing("DELL-0001", for: "builtin", current: []) == memory)
    }

    @Test func uuidMatchingIgnoresCaseAndBraces() {
        let memory = DisplayRoles(remembered: ["external-2": ["DELL-0001"]])
        let lower = Display(uuid: "{dell-0001}", minX: 0, minY: 0, name: "D")
        #expect(memory.assign([lower]).map(\.role) == ["external-2"])
    }

    // MARK: Rol adları

    @Test func externalRoleIndexes() {
        #expect(DisplayRoles.externalIndex(of: "external") == 1)
        #expect(DisplayRoles.externalIndex(of: "external-2") == 2)
        #expect(DisplayRoles.externalIndex(of: "external-1") == nil)
        #expect(DisplayRoles.externalIndex(of: "external-x") == nil)
        #expect(DisplayRoles.externalIndex(of: "builtin") == nil)
        #expect(DisplayRoles.externalRole(1) == "external")
        #expect(DisplayRoles.externalRole(3) == "external-3")
    }

    // MARK: Arayüz adları

    @Test func externalScreensAreNamedByRoleEverywhere() {
        #expect(DisplayRoles.displayName(role: "external", name: "LG HDR 4K") == "Extra monitor")
        #expect(DisplayRoles.displayName(role: "external-2", name: "LG HDR 4K") == "Monitor 2")
        #expect(DisplayRoles.displayName(role: "builtin", name: "Built-in Display") == "Built-in Display")
        #expect(DisplayRoles.displayName(role: "builtin", name: nil) == "builtin")
        // "Neden burada?" metni de rol adını kullanır, model adını değil.
        let rule = Rule(appName: "Mail", bundleID: "com.apple.mail", tokens: [],
                        docked: Destination(screen: "external-2", desktop: 2, layout: .full))
        let match = Routing.Match(destination: rule.docked!, ruleID: rule.id, rule: rule)
        let reason = Routing.reason(for: match, screenName: "LG HDR 4K") ?? ""
        #expect(reason.contains("Monitor 2 · Desktop 2"))
        #expect(!reason.contains("LG HDR 4K"))
        // Sabitleme panelindeki Display menüsü ve açılır liste de (KnownScreen
        // üzerinden) rol adını gösterir; kart başlığıyla çelişmez.
        let external = KnownScreen(id: "external", name: "Studio Display", aspect: 1.78)
        let second = KnownScreen(id: "external-2", name: "LG HDR 4K", aspect: 1.78)
        let builtin = KnownScreen(id: "builtin", name: "Built-in Display", aspect: 1.55)
        #expect(external.roleName == "Extra monitor")
        #expect(second.roleName == "Monitor 2")
        #expect(builtin.roleName == "Built-in Display")
    }

    @Test func roleNamesAreTranslated() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/tr.lproj/Localizable.strings")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains(#""Extra monitor" = "Ekstra monitör";"#))
        #expect(text.contains(#""Monitor %ld" = "%ld. monitör";"#))
    }

    // MARK: Eksik ekran

    @Test func missingSecondMonitorFallsBackToFirstExternal() {
        let both: Set<String> = ["builtin", "external", "external-2"]
        let one: Set<String> = ["builtin", "external"]
        let none: Set<String> = ["builtin"]
        #expect(DisplayRoles.effectiveScreen("external-2", connected: both, fallback: true) == "external-2")
        #expect(DisplayRoles.effectiveScreen("external-2", connected: one, fallback: true) == "external")
        #expect(DisplayRoles.effectiveScreen("external-3", connected: one, fallback: true) == "external")
        #expect(DisplayRoles.effectiveScreen("external-2", connected: one, fallback: false) == nil)
        #expect(DisplayRoles.effectiveScreen("external-2", connected: none, fallback: true) == nil)
        #expect(DisplayRoles.effectiveScreen("external", connected: none, fallback: true) == nil)
        #expect(DisplayRoles.effectiveScreen("builtin", connected: one, fallback: true) == "builtin")
    }

    @Test func resolveTargetAppliesTheFallbackOnlyWhenAsked() {
        let screens = [
            ScreenInfo(id: "builtin", uuid: "B", name: "B", isBuiltin: true,
                       frame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
                       visibleFrame: CGRect(x: 0, y: 0, width: 1710, height: 1074)),
            ScreenInfo(id: "external", uuid: "E", name: "E", isBuiltin: false,
                       frame: CGRect(x: 0, y: 1112, width: 1920, height: 1080),
                       visibleFrame: CGRect(x: 0, y: 1112, width: 1920, height: 1050)),
        ]
        let rule = Destination(screen: "external-2", desktop: 3, layout: .leftHalf)
        let on = Router.resolveTarget(rule, nameSpaces: [:], holdNames: false, displays: [],
                                      screens: screens, displayFallback: true)
        #expect(on?.screen == "external")
        #expect(on?.desktop == 3)
        #expect(on?.layout == .leftHalf)
        let off = Router.resolveTarget(rule, nameSpaces: [:], holdNames: false, displays: [],
                                       screens: screens, displayFallback: false)
        #expect(off == rule)
    }

    // MARK: Kayıt

    @Test func documentWithoutFieldDecodesDefaultsAndOmitsOnWrite() throws {
        let doc = Document()
        let data = try JSONEncoder().encode(doc)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("displayRoles"))
        let back = try JSONDecoder().decode(Document.self, from: data)
        #expect(back.displayRoles == DisplayRoles())
        #expect(back.displayRoles.fallbackToFirstExternal)
    }

    @Test func documentRoundTripsRoles() throws {
        var doc = Document()
        doc.displayRoles = DisplayRoles(remembered: ["external": ["A"], "external-2": ["B", "C"]],
                                        fallbackToFirstExternal: false)
        let back = try JSONDecoder().decode(Document.self, from: JSONEncoder().encode(doc))
        #expect(back.displayRoles == doc.displayRoles)
    }

    @Test func decodingCleansForeignRolesAndNormalizes() throws {
        let json = #"{"remembered":{"builtin":["X"],"external":["{ab-1}","AB-1",""],"external-2":[]}}"#
        let roles = try JSONDecoder().decode(DisplayRoles.self, from: Data(json.utf8))
        #expect(roles.remembered == ["external": ["AB-1"]])
        #expect(roles.fallbackToFirstExternal)
    }

    @Test func badRolesFieldDoesNotBreakTheDocument() throws {
        var object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(Document())) as! [String: Any]
        object["displayRoles"] = "garbage"
        let data = try JSONSerialization.data(withJSONObject: object)
        let back = try JSONDecoder().decode(Document.self, from: data)
        #expect(back.displayRoles == DisplayRoles())
    }

    @Test func historyMatchingIgnoresRoles() {
        var a = Document()
        let b = a
        a.displayRoles = DisplayRoles(remembered: ["external": ["A"]])
        #expect(ChangeHistory.matches(a, b))
    }

    // MARK: URL komutları

    @Test func urlCommandsParse() {
        #expect(URLCommand.parse(URL(string: "deskmap://screen-role/ABCD-1234/External-2")!)
                == .screenRole(display: "ABCD-1234", role: "external-2"))
        #expect(URLCommand.parse(URL(string: "deskmap://screen-role/ABCD/builtin")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://screen-role/ABCD")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://screen-role-forget")!) == .forgetScreenRoles)
        #expect(URLCommand.parse(URL(string: "deskmap://screen-fallback/off")!) == .screenFallback(false))
        #expect(URLCommand.parse(URL(string: "deskmap://screen-fallback/on")!) == .screenFallback(true))
        #expect(URLCommand.parse(URL(string: "deskmap://screen-fallback/maybe")!) == nil)
    }

    @Test func connectedDisplayMatchesRoleOrUniqueUUIDPrefix() {
        let current: [(role: String, display: Display)] = [
            (role: "external", display: Display(uuid: "ABCD-1111", minX: 0, minY: 0, name: "A")),
            (role: "external-2", display: Display(uuid: "ABCE-2222", minX: 1, minY: 0, name: "B")),
        ]
        #expect(URLCommands.connectedDisplay("external-2", in: current) == "ABCE-2222")
        #expect(URLCommands.connectedDisplay("abcd", in: current) == "ABCD-1111")
        #expect(URLCommands.connectedDisplay("{abce-2222}", in: current) == "ABCE-2222")
        #expect(URLCommands.connectedDisplay("ABC", in: current) == nil)    // çok kısa
        #expect(URLCommands.connectedDisplay("ZZZZ", in: current) == nil)
    }
}

/// ScreenService ile uçtan uca: sahte ekran listesi, sök/tak, öğrenme.
@MainActor
struct DisplayRolesServiceTests {

    private static let builtin = ScreenService.RawDisplay(
        uuid: "BUILTIN", name: "Built-in", isBuiltin: true,
        frame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
        visibleFrame: CGRect(x: 0, y: 0, width: 1710, height: 1074))

    private static func external(_ uuid: String, x: CGFloat, name: String = "Monitor") -> ScreenService.RawDisplay {
        .init(uuid: uuid, name: name, isBuiltin: false,
              frame: CGRect(x: x, y: 1112, width: 1920, height: 1080),
              visibleFrame: CGRect(x: x, y: 1112, width: 1920, height: 1050))
    }

    final class Source { var list: [ScreenService.RawDisplay] = [] }

    @Test func learnsAndKeepsRolesAcrossRearrangeAndUnplug() {
        let source = Source()
        source.list = [Self.builtin, Self.external("DELL", x: -100), Self.external("PEBBLE", x: 1710)]
        let service = ScreenService(displays: { source.list })
        let store = Store(demo: Document())
        let sync = AppModel.syncDisplayRoles(store: store, screens: service)
        defer { _ = sync }
        #expect(service.screens.map(\.id) == ["builtin", "external", "external-2"])
        #expect(store.document.displayRoles.remembered == ["external": ["DELL"], "external-2": ["PEBBLE"]])

        // Yer değiştir: Pebble sola. Roller kalır.
        source.list = [Self.builtin, Self.external("DELL", x: 4000), Self.external("PEBBLE", x: -3000)]
        service.simulateChangeForTesting(settle: true)
        #expect(service.screens.first { $0.uuid == "DELL" }?.id == "external")
        #expect(service.screens.first { $0.uuid == "PEBBLE" }?.id == "external-2")

        // Dell çıkar: Pebble external-2 kalır; geri tak: Dell external.
        source.list = [Self.builtin, Self.external("PEBBLE", x: 1710)]
        service.simulateChangeForTesting(settle: true)
        #expect(service.screens.map(\.id) == ["builtin", "external-2"])
        source.list = [Self.builtin, Self.external("PEBBLE", x: 1710), Self.external("DELL", x: 9000)]
        service.simulateChangeForTesting(settle: true)
        #expect(service.screens.first { $0.uuid == "DELL" }?.id == "external")
    }

    @Test func nothingIsLearnedWhileSettling() {
        let source = Source()
        source.list = [Self.builtin, Self.external("DELL", x: 0)]
        let service = ScreenService(displays: { source.list })
        let store = Store(demo: Document())
        let sync = AppModel.syncDisplayRoles(store: store, screens: service)
        defer { _ = sync }
        source.list = [Self.builtin, Self.external("FLICKER", x: 0)]
        service.simulateChangeForTesting(settle: false)
        #expect(store.document.displayRoles.remembered == ["external": ["DELL"]])
    }

    @Test func choosingInTheStoreRecomputesRolesAndAsksForReplacement() {
        let source = Source()
        source.list = [Self.builtin, Self.external("DELL", x: 0), Self.external("PEBBLE", x: 1920)]
        let service = ScreenService(displays: { source.list })
        let store = Store(demo: Document())
        let sync = AppModel.syncDisplayRoles(store: store, screens: service)
        var settledCount = 0
        let watch = service.settled.sink { settledCount += 1 }
        defer { _ = sync; _ = watch }
        let current = service.connectedExternals.map { (role: $0.role, uuid: $0.display.uuid) }
        store.chooseDisplay("PEBBLE", for: "external", current: current)
        #expect(service.screens.first { $0.uuid == "PEBBLE" }?.id == "external")
        #expect(service.screens.first { $0.uuid == "DELL" }?.id == "external-2")
        #expect(settledCount == 1)
        // Unut: konum sırasına döner (bir sonraki öğrenme yine konumdan).
        store.forgetDisplayRoles()
        #expect(service.screens.first { $0.uuid == "DELL" }?.id == "external")
    }

    @Test func testDisplayIsNotLearned() {
        let source = Source()
        source.list = [Self.builtin, Self.external("TEST", x: 0, name: Store.testDisplayName)]
        let service = ScreenService(displays: { source.list })
        let store = Store(demo: Document())
        let sync = AppModel.syncDisplayRoles(store: store, screens: service)
        defer { _ = sync }
        #expect(store.document.displayRoles.remembered.isEmpty)
    }
}
