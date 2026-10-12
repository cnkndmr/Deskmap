import Foundation
import Testing
@testable import Deskmap

/// Mission Control'de silinen masaüstü: pinler ve ad hayalette saklanır,
/// sonrakiler kayar; geri getirme; silmeyi yakalama.
struct GhostDesktopTests {

    private func rule(_ app: String, _ desktop: Int, screen: String = "external") -> Rule {
        var r = Rule(appName: app, bundleID: "b.\(app)", tokens: [])
        r.docked = Destination(screen: screen, desktop: desktop)
        return r
    }

    @Test func pinsAndNameGoToGhostLaterPinsShift() throws {
        var d = Document()
        d.rules = [rule("A", 2), rule("B", 3), rule("C", 1), rule("L", 2, screen: "builtin")]
        d.setDesktopName("Nova", screen: "external", desktop: 2, mode: .docked)
        let made = d.ghostDesktop(on: "external", desktop: 2, modes: Mode.allCases)
        let ghost = try #require(made)
        #expect(ghost.name == "Nova")
        #expect(ghost.pins.map(\.rule.appName) == ["A"])
        // A kuralı başka hedefi olmadığı için kalktı; B bir yukarı; C ve laptop aynı.
        #expect(d.rules.map(\.appName) == ["B", "C", "L"])
        #expect(d.rules.first { $0.appName == "B" }?.docked?.desktop == 2)
        #expect(d.rules.first { $0.appName == "C" }?.docked?.desktop == 1)
        #expect(d.rules.first { $0.appName == "L" }?.docked?.desktop == 2)
        #expect(d.desktopNames(for: .docked)["external"] == nil)
        #expect(d.ghosts(on: "external").count == 1)
    }

    @Test func emptyDesktopMakesNoGhostButStillShifts() {
        var d = Document()
        d.rules = [rule("B", 3)]
        let made = d.ghostDesktop(on: "external", desktop: 2, modes: Mode.allCases)
        #expect(made == nil)
        #expect(d.rules.first?.docked?.desktop == 2)
        #expect(d.ghostDesktops.isEmpty)
    }

    @Test func inactiveProfilesAreHandledToo() throws {
        var d = Document()
        d.rules = [rule("A", 2), rule("B", 3)]
        let first = d.activeProfileID
        d.addProfile(named: "İkinci", copyingCurrent: true)
        let made = d.ghostDesktop(on: "external", desktop: 2, modes: Mode.allCases)
        let ghost = try #require(made)
        // Hayaletler profil başına: her profilin hayaleti yalnız kendi pinini tutar.
        #expect(ghost.pins.count == 1)
        #expect(ghost.pins.allSatisfy { $0.profileID == d.activeProfileID })
        let other = try #require(d.profiles.first { $0.id == first })
        #expect(other.ghostDesktops.count == 1)
        #expect(other.ghostDesktops.first?.pins.map(\.profileID) == [first])
        #expect(other.rules.map(\.appName) == ["B"])
        #expect(other.rules.first?.docked?.desktop == 2)
    }

    @Test func restoreBringsPinsAndNameBackToNewDesktop() throws {
        var d = Document()
        var both = rule("A", 2)
        both.undocked = Destination(screen: "builtin", desktop: 1)
        d.rules = [both, rule("X", 2)]
        d.setDesktopName("Nova", screen: "external", desktop: 2, mode: .docked)
        let made = d.ghostDesktop(on: "external", desktop: 2, modes: Mode.allCases)
        let ghost = try #require(made)
        // A'nın laptop hedefi kaldığı için kural durdu; X tamamen kalktı.
        #expect(d.rules.map(\.appName) == ["A"])
        d.restoreGhost(ghost.id, desktop: 4, space: 99, mode: .docked)
        #expect(d.rules.first { $0.appName == "A" }?.docked?.desktop == 4)
        #expect(d.rules.first { $0.appName == "A" }?.undocked?.desktop == 1)
        #expect(d.rules.first { $0.appName == "X" }?.docked == Destination(screen: "external", desktop: 4))
        #expect(d.desktopName(screen: "external", desktop: 4, mode: .docked) == "Nova")
        #expect(d.desktopNameSpaces["docked|external"]?["4"] == 99)
        #expect(d.ghostDesktops.isEmpty)
    }

    @Test func discardForgetsGhost() throws {
        var d = Document()
        d.rules = [rule("A", 2)]
        let made = d.ghostDesktop(on: "external", desktop: 2, modes: Mode.allCases)
        let ghost = try #require(made)
        d.discardGhost(ghost.id)
        #expect(d.ghostDesktops.isEmpty && d.rules.isEmpty)
    }

    @Test func ghostsRoundTripThroughJSON() throws {
        var d = Document()
        d.rules = [rule("A", 2)]
        d.ghostDesktop(on: "external", desktop: 2, modes: Mode.allCases)
        let decoded = try JSONDecoder().decode(Document.self, from: JSONEncoder().encode(d))
        #expect(decoded.ghostDesktops == d.ghostDesktops)
    }

    @Test func detectsExternalRemovalOnly() {
        let r = Router.externallyRemovedDesktops
        // 2. masaüstü silindi.
        #expect(r(["external": [1, 2, 3]], ["external": [1, 3]]) == ["external": [2]])
        // Başka ekrana taşındı: silme değil.
        #expect(r(["external": [1, 2, 3]], ["external": [1, 3], "builtin": [9, 2]]).isEmpty)
        // Ekran yeniden bağlandı, kimlikler yenilendi: silme değil.
        #expect(r(["external": [1, 2]], ["external": [7, 8]]).isEmpty)
        // Ekran yok (bağlantı kesildi): dokunulmaz.
        #expect(r(["external": [1, 2]], ["builtin": [9]]).isEmpty)
        // İki silme: büyükten küçüğe (numaralar kaymadan işlenir).
        #expect(r(["external": [1, 2, 3, 4]], ["external": [1, 3]]) == ["external": [4, 2]])
        // Ekleme silme değil.
        #expect(r(["external": [1]], ["external": [1, 5]]).isEmpty)
    }
}
