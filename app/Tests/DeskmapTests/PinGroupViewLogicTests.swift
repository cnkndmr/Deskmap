import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Pin grubu kutusunun saf görünüm kararları: sayı ve "başka yerde de"
/// etiketleri, sağ tık hedefleri, açılabilir üyeler, üye yerleri.
struct PinGroupViewLogicTests {

    private let group = PinGroup(id: "g1", name: "Nova drafts")

    private func rule(_ id: String, group: String? = "g1",
                      docked: Destination? = Destination(screen: "builtin", desktop: 3),
                      undocked: Destination? = nil) -> Rule {
        Rule(id: id, appName: "Preview", bundleID: "com.apple.Preview", tokens: [id],
             docked: docked, undocked: undocked, groupID: group)
    }

    private func window(_ id: CGWindowID, _ title: String) -> Router.WindowSnapshot {
        Router.WindowSnapshot(id: id, pid: 1, appName: "Preview", bundleID: "com.apple.Preview",
                              title: title, placement: Router.Placement(screen: "builtin", desktop: 3),
                              frame: nil, isMinimized: false)
    }

    @Test func countLabelUsesSingularForOneWindow() {
        #expect(PinGroupBoxView.countLabel(windows: 1, closed: 0) == "1 window")
        #expect(PinGroupBoxView.countLabel(windows: 3, closed: 0) == "3 windows")
        #expect(PinGroupBoxView.countLabel(windows: 0, closed: 2) == "2 closed")
        #expect(PinGroupBoxView.countLabel(windows: 2, closed: 1) == "2 + 1 closed")
    }

    @Test func elsewhereLabelJoinsDesktopsAndScreens() {
        var box = PinGroupBox(group: group, windows: [], closed: [])
        #expect(PinGroupBoxView.elsewhereLabel(box) == nil)
        box.elsewhere = [2, 5]
        #expect(PinGroupBoxView.elsewhereLabel(box) == "also on Desktop 2, 5")
        box.otherScreens = true
        #expect(PinGroupBoxView.elsewhereLabel(box) == "also on Desktop 2, 5 · also on another screen")
        box.elsewhere = []
        #expect(PinGroupBoxView.elsewhereLabel(box) == "also on another screen")
    }

    /// Sağ tık seçimdeyse bütün seçime (çipler + pencerelerin kazanan
    /// kuralları, belge sırasıyla), değilse yalnız tıklanana uygulanır.
    @Test func menuTargetsExpandToTheSelection() {
        let rules = [rule("a"), rule("b"), rule("c"), rule("d")]
        let windows = [window(1, "c"), window(2, "x")]
        let ruleFor: (Router.WindowSnapshot) -> Rule? = { w in rules.first { $0.id == w.title } }
        #expect(PinGroupMenu.targetIDs(ruleID: "d", windowID: nil, rules: rules, selectedRules: ["a"],
                                       selection: [1], windows: windows, ruleFor: ruleFor) == ["d"])
        #expect(PinGroupMenu.targetIDs(ruleID: "d", windowID: nil, rules: rules, selectedRules: ["d", "a"],
                                       selection: [1, 2], windows: windows, ruleFor: ruleFor)
                == ["a", "c", "d"])
        #expect(PinGroupMenu.targetIDs(ruleID: "c", windowID: 1, rules: rules, selectedRules: ["b"],
                                       selection: [1], windows: windows, ruleFor: ruleFor) == ["b", "c"])
    }

    /// Öbür planın tepsi çipi bu plandan gruba eklenemez.
    @Test func onlyRulesPlacedInThisModeAreAddable() {
        let rules = [rule("a"), rule("tray", docked: nil, undocked: Destination(screen: "builtin", desktop: 1))]
        #expect(PinGroupMenu.addable(["a", "tray"], rules: rules, mode: .docked) == ["a"])
        #expect(PinGroupMenu.addable(["tray"], rules: rules, mode: .docked).isEmpty)
        #expect(PinGroupMenu.addable(["tray"], rules: rules, mode: .undocked) == ["tray"])
    }

    /// Kapalı üye yalnız kullanılabilir ve var olan bir masaüstüne
    /// açılabiliyorsa "Tümünü aç"a girer.
    @Test func placeableDropsMissingScreensAndDesktops() {
        let rules = [rule("ok"), rule("missingDesktop", docked: Destination(screen: "builtin", desktop: 9)),
                     rule("unplugged", docked: Destination(screen: "external", desktop: 1)),
                     rule("unknownCount", docked: Destination(screen: "external-2", desktop: 4))]
        let winner: (Rule) -> Destination? = { $0.docked?.screen == "external" ? nil : $0.docked }
        let open = PinBatch.placeable(rules, desktopCounts: ["builtin": 4], winner: winner)
        #expect(open.map(\.id) == ["ok", "unknownCount"])
    }

    /// Üye yerleri kazanan yerden gelir, ilk yerden değil; bu moddaki
    /// üyesi olmayan grup boş liste alır.
    @Test func memberPlacesUseTheWinningPlace() {
        var d = Document()
        d.rules = [rule("a"), rule("b", docked: Destination(screen: "external", desktop: 2)),
                   rule("c", docked: nil, undocked: Destination(screen: "builtin", desktop: 1))]
        d.pinGroups = [group]
        let box = PinGroupBox(group: group, windows: [], closed: [])
        let moved = Destination(screen: "builtin", desktop: 5)
        let places = PinGroupLayout.memberPlaces(for: [box], document: d, mode: .docked,
                                                 winner: { $0.id == "b" ? moved : $0.docked })
        #expect(places["g1"] == [Destination(screen: "builtin", desktop: 3), moved])
        var boxes = [box]
        PinGroupLayout.annotate(&boxes, screen: "builtin", desktop: 3, memberPlaces: places)
        #expect(boxes[0].elsewhere == [5])
        #expect(!boxes[0].otherScreens)
    }
}

/// `UIState`'in pin grubu istekleri: adlandırma isteği kendiliğinden düşer,
/// "Tümünü aç" grup başına bir kez sürer.
@MainActor
struct PinGroupUIStateTests {

    @Test func unclaimedRenameRequestExpires() async throws {
        let ui = UIState()
        ui.requestPinGroupRename("g1", expiresAfter: 0.05)
        #expect(ui.renamePinGroupRequest == "g1")
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(ui.renamePinGroupRequest == nil)
    }

    /// Yeni istek eskisinin süresini sıfırlar; eski zamanlayıcı onu silmez.
    @Test func newerRenameRequestSurvivesTheOlderTimer() async throws {
        let ui = UIState()
        ui.requestPinGroupRename("g1", expiresAfter: 0.05)
        ui.requestPinGroupRename("g2", expiresAfter: 5)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(ui.renamePinGroupRequest == "g2")
    }

    @Test func openingGuardIsPerGroup() {
        let ui = UIState()
        #expect(ui.beginOpeningPinGroup("g1"))
        #expect(!ui.beginOpeningPinGroup("g1"))
        #expect(ui.beginOpeningPinGroup("g2"))
        ui.endOpeningPinGroup("g1")
        #expect(ui.beginOpeningPinGroup("g1"))
    }
}
