import Testing
@testable import Deskmap

/// Pinli pencere satırının "Gönder" menüsündeki hedef listesi.
struct SendMenuTests {

    private let screens = [KnownScreen(id: "builtin", name: "Dahili", aspect: 1.55),
                           KnownScreen(id: "external", name: "LG", aspect: 1.78)]

    @Test func listsEveryScreenWithMapDesktopCountAndMarksCurrent() {
        let targets = WindowRow.sendTargets(
            screens: screens, tileCounts: ["builtin": 2, "external": 4],
            current: Destination(screen: "external", desktop: 3))
        #expect(targets.map(\.screen) == ["builtin", "external"])
        #expect(targets.map(\.name) == ["Dahili", "LG"])
        #expect(targets[0].desktops.map(\.desktop) == [1, 2])
        #expect(targets[1].desktops.map(\.desktop) == [1, 2, 3, 4])
        #expect(targets[0].desktops.allSatisfy { !$0.isCurrent })
        #expect(targets[1].desktops.filter(\.isCurrent).map(\.desktop) == [3])
    }

    @Test func missingCountFallsBackToOneDesktop() {
        let targets = WindowRow.sendTargets(screens: screens, tileCounts: [:], current: nil)
        #expect(targets.map { $0.desktops.count } == [1, 1])
    }

    @Test func currentBeyondCountIsStillListed() {
        let targets = WindowRow.sendTargets(
            screens: screens, tileCounts: ["builtin": 1],
            current: Destination(screen: "builtin", desktop: 3))
        #expect(targets[0].desktops.map(\.desktop) == [1, 2, 3])
        #expect(targets[0].desktops.last?.isCurrent == true)
    }
}
