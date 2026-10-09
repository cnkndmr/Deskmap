import Foundation
import Testing
@testable import Deskmap

/// Adlı masaüstü hataları: adsız masaüstüne taşınan pin öbür kurulumun
/// pinini silmesin; Deskmap'te sıralama space bağlarını çaprazlamasın.
struct DesktopBindingFixTests {

    private let D = Mode.docked, U = Mode.undocked

    private func linked() -> Document {
        var d = Document()
        d.desktopNames = [
            "docked|external": ["1": "Notes Hub", "2": "Nova2"],
            "undocked|builtin": ["5": "Notes Hub", "6": "Nova2"],
        ]
        d.desktopNameSpaces = [
            "docked|external": ["1": 1027, "2": 1028],
            "undocked|builtin": ["5": 1027, "6": 1028],
        ]
        return d
    }

    @Test func movingPinToUnnamedDesktopKeepsOtherModePin() throws {
        var d = linked()
        let id = d.pin(Rule(appName: "Mail", bundleID: "m", tokens: []),
                       destination: Destination(screen: "external", desktop: 1), mode: D)
        #expect(d.rule(id)?.undocked == Destination(screen: "builtin", desktop: 5))
        d.setDestination(Destination(screen: "external", desktop: 4), for: id, mode: D)
        let rule = try #require(d.rule(id))
        #expect(rule.docked?.desktop == 4)
        #expect(rule.undocked == Destination(screen: "builtin", desktop: 5))
        // Pin kaldırılınca adlı karşılık yine kalkar.
        d.setDestination(Destination(screen: "external", desktop: 2), for: id, mode: D)
        #expect(d.rule(id)?.undocked == Destination(screen: "builtin", desktop: 5))
    }

    @Test func liveReorderPermutesBindingsInBothModes() {
        var d = linked()
        d.rules = [Rule(appName: "A", bundleID: "a", tokens: [],
                        docked: Destination(screen: "external", desktop: 1),
                        undocked: Destination(screen: "builtin", desktop: 5))]
        d.moveDesktop(on: "external", from: 1, to: 2, count: 3, mode: D, sharedLaptop: true,
                      liveSpaces: [1027, 1028, 1029])
        #expect(d.desktopNames["docked|external"] == ["1": "Nova2", "2": "Notes Hub"])
        // Ad yeni yerinin kimliğine bağlı; öbür kurulumda aynı ad aynı kimlik.
        #expect(d.desktopNameSpaces["docked|external"] == ["1": 1027, "2": 1028])
        #expect(d.desktopNameSpaces["undocked|builtin"] == ["5": 1028, "6": 1027])
        #expect(d.rules[0].docked?.desktop == 2)
        #expect(d.rules[0].undocked?.desktop == 5)
        // Gezgin bağ eşitleme ve tarama artık hiçbir şeyi değiştirmez.
        var synced = d
        synced.syncTravellingBindings(mode: D)
        #expect(synced == d)
        let result = d.reconcileNames(spaces: ["external": [1027, 1028, 1029]],
                                      seen: [1027, 1028, 1029], mode: D)
        #expect(result.moves.isEmpty && result.dropped.isEmpty)
        #expect(d.desktopNames["docked|external"] == ["1": "Nova2", "2": "Notes Hub"])
    }

    @Test func liveReorderMovesLoneOtherModeBinding() {
        // Öbür kurulumda yalnız taşınan ad bağlı: eskiden takas yapılamadığı
        // için laptop bağı eski kimlikte kalıyordu (çaprazlama).
        var d = Document()
        d.desktopNames = ["docked|external": ["1": "Notes Hub"], "undocked|builtin": ["5": "Notes Hub"]]
        d.desktopNameSpaces = ["docked|external": ["1": 1027], "undocked|builtin": ["5": 1027]]
        d.moveDesktop(on: "external", from: 1, to: 3, count: 3, mode: D, sharedLaptop: true,
                      liveSpaces: [1027, 1028, 1029])
        #expect(d.desktopNameSpaces["docked|external"] == ["3": 1029])
        #expect(d.desktopNameSpaces["undocked|builtin"] == ["5": 1029])
    }

    @Test func builtinLiveReorderBindsBothModes() {
        var d = Document()
        d.setDesktopName("AI", screen: "builtin", desktop: 3, mode: D, space: 30)
        d.moveDesktop(on: "builtin", from: 3, to: 1, count: 3, mode: D, sharedLaptop: true,
                      liveSpaces: [10, 20, 30])
        #expect(d.desktopNames["docked|builtin"] == ["1": "AI"])
        #expect(d.desktopNames["undocked|builtin"] == ["1": "AI"])
        #expect(d.desktopNameSpaces["docked|builtin"] == ["1": 10])
        #expect(d.desktopNameSpaces["undocked|builtin"] == ["1": 10])
    }

    @Test func builtinReorderDoesNotRebindForeignUndockedName() {
        var d = Document()
        d.desktopNames = ["docked|builtin": ["8": "A", "9": "B"], "undocked|builtin": ["8": "MD2", "9": "B"]]
        d.desktopNameSpaces = ["docked|builtin": ["8": 80, "9": 90], "undocked|builtin": ["8": 1031, "9": 90]]
        d.moveDesktop(on: "builtin", from: 8, to: 9, count: 9, mode: D, sharedLaptop: true,
                      liveSpaces: [1, 2, 3, 4, 5, 6, 7, 80, 90])
        #expect(d.desktopNames["undocked|builtin"] == ["8": "B", "9": "MD2"])
        #expect(d.desktopNameSpaces["undocked|builtin"]?["9"] == nil)
        #expect(d.desktopNameSpaces["undocked|builtin"]?["8"] == 80)
    }

    @Test func reorderWithoutLiveSpacesKeepsOldBehaviour() {
        var d = linked()
        d.moveDesktop(on: "external", from: 1, to: 2, count: 3, mode: D, sharedLaptop: true)
        #expect(d.desktopNames["docked|external"] == ["1": "Nova2", "2": "Notes Hub"])
        #expect(d.desktopNameSpaces["undocked|builtin"] == ["5": 1027, "6": 1028])
    }

    @Test func inAppRemovalLeavesRestorableGhost() throws {
        var d = linked()
        d.rules = [Rule(appName: "A", bundleID: "a", tokens: [],
                        docked: Destination(screen: "external", desktop: 1))]
        let made = d.ghostDesktop(on: "external", desktop: 1, modes: Mode.allCases)
        let ghost = try #require(made)
        #expect(ghost.name == "Notes Hub" && ghost.pins.count == 1)
        #expect(d.desktopNames["docked|external"] == ["1": "Nova2"])
        d.restoreGhost(ghost.id, desktop: 3, mode: D)
        #expect(d.rules.first?.docked?.desktop == 3)
        #expect(d.desktopName(screen: "external", desktop: 3, mode: D) == "Notes Hub")
    }
}
