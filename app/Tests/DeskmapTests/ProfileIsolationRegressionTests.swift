import Foundation
import Testing
@testable import Deskmap

/// Regressions: physical desktop operations in one profile must not shift
/// another profile's pins twice or through the other profile's names.
struct ProfileIsolationRegressionTests {

    private let D = Mode.docked, U = Mode.undocked

    private func rule(_ app: String, _ desktop: Int, screen: String = "external",
                      mode: Mode = .docked) -> Rule {
        var r = Rule(appName: app, bundleID: "b.\(app)", tokens: [])
        r[mode] = Destination(screen: screen, desktop: desktop)
        return r
    }

    private func rules(_ d: Document, _ id: String) -> [Rule] {
        id == d.activeProfileID ? d.rules : (d.profiles.first { $0.id == id }?.rules ?? [])
    }

    @Test func inAppMoveShiftsOtherProfilePinOnce() {
        var d = Document()
        let b = d.activeProfileID
        d.rules = [rule("Pin", 2)]
        d.setDesktopName("Mail", screen: "external", desktop: 1, mode: D, space: 11)
        d.syncActiveProfile()
        _ = d.addProfile(named: "A")
        d.moveDesktop(on: "external", from: 1, to: 3, count: 3, mode: D,
                      liveSpaces: [11, 22, 33])
        #expect(rules(d, b).first?.docked?.desktop == 1)
        let result = d.reconcileNames(spaces: ["external": [11, 22, 33]], seen: [11, 22, 33], mode: D)
        #expect(result.ghostGroups.isEmpty)
        #expect(rules(d, b).first?.docked?.desktop == 1)
    }

    @Test func noFreeSlotDropInOtherProfileIsNotADeletion() {
        var d = Document()
        let b = d.activeProfileID
        d.desktopNames["docked|external"] = ["1": "Y", "3": "X"]
        d.desktopNameSpaces["docked|external"] = ["1": 33]
        d.syncActiveProfile()
        _ = d.addProfile(named: "A")
        d.rules = [rule("P3", 3), rule("P2", 2)]
        let result = d.reconcileNames(spaces: ["external": [11, 22, 33]], seen: [11, 22, 33], mode: D)
        // Masaüstü silinmedi: düşen ad değil, yerleşemeyen ad (4d5ded8).
        #expect(result.otherDropped[b] == nil)
        #expect(result.unplaced.map(\.name) == ["X"])
        #expect(result.unplaced.first?.deleted == false)
        #expect(result.ghostGroups.isEmpty)
        #expect(d.rules.map { $0.docked?.desktop } == [3, 2])
        let other = d.profiles.first { $0.id == b }
        #expect(other?.ghostDesktops.map(\.name) == ["X"])
        #expect(d.ghostDesktops.isEmpty)
    }

    @Test func nilSpaceDeletedDropsGroupBySlot() {
        var r = ReconcileResult()
        let place = NamePlace(mode: D, screen: "external", desktop: 2, space: nil)
        r.dropped = [DroppedName(place: place, name: "A")]
        r.otherDropped = ["p": [DroppedName(place: place, name: "B")]]
        #expect(r.ghostGroups.count == 1)
    }

    @Test func removeDesktopUsesEachProfilesOwnNamesForCounterparts() {
        var d = Document()
        let b = d.activeProfileID
        d.rules = [rule("B2", 2, screen: "builtin", mode: U), rule("B3", 3, screen: "builtin", mode: U)]
        d.syncActiveProfile()
        _ = d.addProfile(named: "A")
        d.setDesktopName("Mail", screen: "external", desktop: 3, mode: D)
        d.setDesktopName("Mail", screen: "builtin", desktop: 2, mode: U)
        d.removeDesktop(on: "external", desktop: 3, modes: [D])
        #expect(rules(d, b).map { $0.undocked?.desktop } == [2, 3])
    }

    @Test func copyLayoutKeepsOtherProfilesQueuedRemovals() {
        var d = Document()
        let b = d.activeProfileID
        d.removeDesktopLater(on: "builtin", desktop: 4, mode: D, existing: true, space: 44)
        d.syncActiveProfile()
        _ = d.addProfile(named: "A")
        d.setDesktopName("Lap", screen: "builtin", desktop: 1, mode: U)
        _ = d.copyLayout(from: U, to: D)
        #expect(d.pendingRemovals(mode: D, screen: "builtin").map(\.profileID) == [b])
    }

    @Test func copyLayoutClearsOwnQueuedRemovals() {
        var d = Document()
        d.removeDesktopLater(on: "builtin", desktop: 4, mode: D, existing: true, space: 44)
        d.setDesktopName("Lap", screen: "builtin", desktop: 1, mode: U)
        _ = d.copyLayout(from: U, to: D)
        #expect(d.pendingRemovals(mode: D, screen: "builtin").isEmpty)
    }
}
