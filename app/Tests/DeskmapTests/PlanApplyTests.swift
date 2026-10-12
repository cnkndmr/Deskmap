import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Plan uygulaması (docs/desktop-names-v2.md §P, B satırları 1–7, 18–19, C).
struct PlanApplyTests {

    private func n(_ id: String, _ space: UInt64?) -> DesktopName { DesktopName(id: id, name: id, space: space) }
    private func s(_ role: String, _ desktop: Int) -> Slot { Slot(screen: role, desktop: desktop) }

    /// Monitör çıktı: macOS monitör masaüstülerini laptopun sonuna ekledi.
    private func unplugInput() -> PlanApply.Input {
        PlanApply.Input(
            mode: .undocked,
            live: ["builtin": [5, 4, 6, 8, 1652, 1653, 1678, 1679, 1680, 1681, 1674, 1673, 1672, 1032]],
            contents: [5: [1, 2], 4: [3], 6: [4], 8: [5], 1652: [6], 1653: [7],
                       1681: [10, 11], 1674: [12], 1673: [13], 1672: [14, 15]],
            names: [n("AI", 8), n("HUB", 1652), n("NOVA", 1653), n("ORION", 1681), n("EXPO", 1674), n("LUMEN", 1672)],
            plans: ["builtin": ["", "", "", "AI", "HUB", "NOVA", "EXPO", "LUMEN", "ORION", ""]],
            arriving: ["builtin": [[13]]],
            leftovers: [1681, 1674, 1673, 1672, 1032])
    }

    // MARK: - Satır 1

    @Test func unplugPlacesNamesInPlannedOrder() {
        let out = PlanApply.compute(unplugInput())
        #expect(out.rebinds == ["EXPO": s("builtin", 7), "LUMEN": s("builtin", 8), "ORION": s("builtin", 9)])
        #expect(Set(out.moves) == [
            .init(window: 12, to: s("builtin", 7)), .init(window: 14, to: s("builtin", 8)),
            .init(window: 15, to: s("builtin", 8)), .init(window: 10, to: s("builtin", 9)),
            .init(window: 11, to: s("builtin", 9)), .init(window: 13, to: s("builtin", 10))])
        #expect(out.creates.isEmpty)
        #expect(out.movedNames == 3)
        #expect(out.spaceMap[1674] == s("builtin", 7))
    }

    @Test func unplugKeepsUnnamedExternalDesktopsSeparate() {
        var input = unplugInput()
        input.contents[1032] = [16]
        input.arriving = ["builtin": [[13], [16]]]
        let out = PlanApply.compute(input)
        #expect(out.moves.contains(.init(window: 13, to: s("builtin", 10))))
        // İkinci grup "" yer kalmadığından planın sonuna eklenir, birleştirilmez.
        let target = out.moves.first { $0.window == 16 }?.to
        #expect(target != nil && target != s("builtin", 10))
        #expect(target!.desktop > 10)
    }

    /// Adsız monitör masaüstlerinin pencereleri "" yerlere soldan sağa (park
    /// kaydı Router'da; burada yerleşim).
    @Test func unplugParksUnnamedExternalWindows() {
        var input = unplugInput()
        input.plans["builtin"] = ["", "", "", "AI", "HUB", "NOVA", "EXPO", "LUMEN", "ORION", "", ""]
        input.contents[1680] = []
        let out = PlanApply.compute(input)
        #expect(out.moves.first { $0.window == 13 }?.to == s("builtin", 10))
    }

    @Test func unplugRemovesOnlyEmptyLeftovers() {
        let out = PlanApply.compute(unplugInput())
        #expect(out.removals == [1032, 1672, 1673, 1674])
        var keep = unplugInput()
        keep.contents[1032] = [99]
        #expect(!PlanApply.compute(keep).removals.contains(1032))
    }

    // MARK: - Satır 2–4

    @Test func replugSameIdsNoMoves() {
        let out = PlanApply.compute(PlanApply.Input(
            mode: .docked, live: ["external": [1681, 1674, 1673, 1672], "builtin": [5, 8]],
            contents: [1681: [1], 1674: [2], 1672: [3], 8: [4]],
            names: [n("ORION", 1681), n("EXPO", 1674), n("LUMEN", 1672), n("AI", 8)],
            plans: ["external": ["ORION", "EXPO", "", "LUMEN"], "builtin": ["", "AI"]]))
        #expect(out.isEmpty)
    }

    @Test func replugReturnsParkedWindow() {
        let out = PlanApply.compute(PlanApply.Input(
            mode: .docked, live: ["external": [1681, 1674, 1673], "builtin": [5, 1680]],
            contents: [1681: [1], 1680: [13]], names: [n("ORION", 1681)],
            plans: ["external": ["ORION", "", ""]],
            parked: [.init(window: 13, role: "external", desktop: 3, space: 1673)]))
        #expect(out.moves == [.init(window: 13, to: s("external", 3))])
    }

    @Test func replugNewSpacesMovesContentAndRebinds() {
        let out = PlanApply.compute(PlanApply.Input(
            mode: .docked, live: ["external": [2001], "builtin": [5, 4, 6, 8, 1652, 1653, 1678, 1679, 1680]],
            contents: [1680: [10, 11], 1678: [12], 1679: [14]],
            names: [n("ORION", 1680), n("EXPO", 1678), n("LUMEN", 1679), n("AI", 8)],
            plans: ["external": ["ORION", "EXPO", "", "LUMEN"], "builtin": ["", "", "", "AI", "", ""]],
            leftovers: [2001]))
        #expect(out.creates == ["external": 3])
        #expect(out.rebinds == ["ORION": s("external", 1), "EXPO": s("external", 2), "LUMEN": s("external", 4)])
        #expect(Set(out.moves.map(\.window)) == [10, 11, 12, 14])
        #expect(out.removals == [1680, 1679, 1678])
    }

    @Test func createsMissingCappedAt8() {
        let names = (1...12).map { n("N\($0)", nil) }
        let out = PlanApply.compute(PlanApply.Input(
            mode: .docked, live: ["external": [1]], contents: [:], names: names,
            plans: ["external": names.map(\.id)]))
        #expect(out.creates == ["external": 8])
        #expect(Set(out.skippedNames) == ["N10", "N11", "N12"])
        #expect(out.rebinds["N9"] == s("external", 9))
        #expect(out.rebinds["N10"] == nil)
    }

    /// Açılamayan yere planlı ad yerinde kalır (taşınmaz, kaybolmaz).
    @Test func failedCreateKeepsNamesInPlace() {
        let out = PlanApply.compute(PlanApply.Input(
            mode: .docked, live: ["external": [1], "builtin": [5, 7]], contents: [7: [70]],
            names: [n("K", 7)], plans: ["external": ["", "", "K"]], maxCreatesPerRole: 1))
        #expect(out.skippedNames == ["K"])
        #expect(out.moves.isEmpty && out.rebinds.isEmpty)
    }

    @Test func keepsNonEmptyExtras() {
        let out = PlanApply.compute(PlanApply.Input(
            mode: .docked, live: ["external": [1, 2, 3]], contents: [1: [10], 2: [20]],
            names: [n("A", 1)], plans: ["external": ["A"]], leftovers: [2, 3]))
        #expect(out.removals == [3])
    }

    /// P1: macOS'un açtığı boş fazlalık silinir; önceden var olan boş masaüstü kalır.
    @Test func removesEmptyMacCreatedExtras() {
        let out = PlanApply.compute(PlanApply.Input(
            mode: .docked, live: ["external": [1, 2, 3, 4]], contents: [1: [10]],
            names: [n("A", 1)], plans: ["external": ["A"]], leftovers: [3]))
        #expect(out.removals == [3])
    }

    // MARK: - Satır 5, 7

    /// Yarıda kesme ya da sınır: silme yok (kalan iş sonraki tura).
    @Test func abortCommitsJournalNoRemoval() {
        var input = unplugInput()
        input.maxMoves = 2
        let out = PlanApply.compute(input)
        #expect(out.truncated)
        #expect(out.removals.isEmpty)
        #expect(out.moves.count <= 2)
    }

    @Test func planIsPerRole() {
        let out = PlanApply.compute(PlanApply.Input(
            mode: .docked, live: ["external": [1, 2], "external-2": [3, 4]],
            contents: [2: [20], 3: [30]], names: [n("A", 2), n("B", 3)],
            plans: ["external": ["A"], "external-2": ["", "B"]]))
        #expect(out.rebinds == ["A": s("external", 1), "B": s("external-2", 2)])
    }

    /// P2: başka monitör (başka kimlik, aynı rol): park kaydı role göre döner.
    @Test func parkedRestoredByRole() {
        let out = PlanApply.compute(PlanApply.Input(
            mode: .docked, live: ["external": [900, 901], "builtin": [5, 6]], contents: [6: [13]],
            names: [], plans: ["external": ["", ""]],
            parked: [.init(window: 13, role: "external", displayUUID: "MONITOR-A", desktop: 2, space: 1673)]))
        #expect(out.moves == [.init(window: 13, to: s("external", 2))])
    }

    // MARK: - Satır 18–19 (S1)

    @Test func profileSwitchNoRemoval() {
        var input = unplugInput()
        input.allowRemovals = false
        let out = PlanApply.compute(input)
        #expect(out.removals.isEmpty)
        #expect(!out.moves.isEmpty)
    }

    // MARK: - Güvenlik (C)

    @Test func neverRemovesNonEmpty() {
        let out = PlanApply.compute(PlanApply.Input(
            mode: .docked, live: ["external": [1, 2]], contents: [2: [20]],
            names: [], plans: ["external": [""]], leftovers: [2]))
        #expect(out.removals.isEmpty)
    }

    @Test func unknownEmptinessKeeps() {
        #expect(PlanApply.isEmpty(5, windowSpaces: []) == nil)
        #expect(PlanApply.isEmpty(5, windowSpaces: [[6], nil]) == nil)
        #expect(PlanApply.isEmpty(5, windowSpaces: [[6], [5]]) == false)
        #expect(PlanApply.isEmpty(5, windowSpaces: [[6]]) == true)
    }

    /// Tam ekran pencere içerikte değildir: hiç taşınmaz.
    @Test func fullscreenUntouched() {
        let out = PlanApply.compute(PlanApply.Input(
            mode: .docked, live: ["external": [1, 2]], contents: [2: [20]],
            names: [n("A", 2)], plans: ["external": ["A"]]))
        #expect(!out.moves.contains { $0.window == 99 })
        #expect(out.moves == [.init(window: 20, to: s("external", 1))])
    }

    @Test func allDesktopsWindowsIgnored() {
        #expect(PlanApply.isEmpty(5, windowSpaces: [[5, 6], [7]]) == true)
    }

    @Test func moveFailureKeepsSource() {
        #expect(PlanApply.removalsAfterFailures([1, 2, 3], failed: [20], contents: [20: 2, 30: 3]) == [1, 3])
    }

    @Test func limitsSplitPasses() {
        var input = unplugInput()
        input.maxMoves = 3
        let out = PlanApply.compute(input)
        #expect(out.truncated && out.removals.isEmpty)
        #expect(out.moves.count <= 3)
    }

    @Test func movesOffMeansTrackingOnly() {
        var input = unplugInput()
        input.allowMoves = false
        #expect(PlanApply.compute(input).isEmpty)
    }

    /// Ad hedefi çözümü: adın space'inin canlı yeri; yerleşmemiş ad tutulur.
    @Test func nameTargetResolvesAndUnplacedHolds() {
        let number = Destination(screen: "builtin", desktop: 3)
        #expect(Router.resolveTarget(number, nameSpaces: [:], holdNames: true, displays: [], screens: []) == number)
        let named = Destination(screen: "external", desktop: 2, nameID: "EXPO")
        #expect(Router.resolveTarget(named, nameSpaces: [:], holdNames: false, displays: [], screens: []) == nil)
        #expect(Router.resolveTarget(named, nameSpaces: ["EXPO": 5], holdNames: true, displays: [], screens: []) == nil)
    }
}
