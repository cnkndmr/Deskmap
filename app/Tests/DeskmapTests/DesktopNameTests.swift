import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

private let D = Mode.docked, U = Mode.undocked

private func names(_ d: Document, _ mode: Mode = .docked) -> [String: [String: String]] {
    d.desktopNames(for: mode)
}
private func bound(_ d: Document, _ screen: String, _ mode: Mode = .docked) -> [String: UInt64]? {
    d.desktopNameSpaces[Document.planKey(mode: mode, screen: screen)]
}

/// Masaüstü adları: verme/silme, kuruluma bağlılık, Deskmap işlemlerinde
/// kayma, dosya biçimi, URL komutu.
struct DesktopNameTests {

    private func named(_ pairs: [(String, Int, String)], mode: Mode = .docked) -> Document {
        var document = Document()
        for (screen, desktop, name) in pairs {
            document.setDesktopName(name, screen: screen, desktop: desktop, mode: mode)
        }
        return document
    }

    @Test func setTrimsAndEmptyRemoves() {
        var document = named([("external", 5, "  Nova  ")])
        #expect(document.desktopName(screen: "external", desktop: 5, mode: D) == "Nova")
        document.setDesktopName("   ", screen: "external", desktop: 5, mode: D)
        #expect(document.desktopName(screen: "external", desktop: 5, mode: D) == nil)
        #expect(document.desktopNames.isEmpty)
    }

    @Test func laptopNamesBelongToBothSetupsExternalOnlyToItsOwn() {
        let document = named([("builtin", 3, "Nova"), ("external", 2, "Dell")], mode: D)
        #expect(document.desktopName(screen: "builtin", desktop: 3, mode: U) == "Nova")
        #expect(document.desktopName(screen: "external", desktop: 2, mode: U) == nil)
    }

    @Test func laptopNameIsNotCopiedWhereTheOtherSetupAlreadyHasIt() {
        // Nova monitörlü kurulumda Dell'de; laptop kurulumunda laptop/3'e ad verilir.
        var d = named([("external", 2, "Nova")], mode: D)
        d.setDesktopName("Nova", screen: "builtin", desktop: 3, mode: U)
        #expect(names(d, U) == ["builtin": ["3": "Nova"]])
        #expect(names(d, D) == ["external": ["2": "Nova"]])
    }

    @Test func movingToMonitorKeepsTheLaptopPlaceInTheLaptopSetup() {
        // Nova laptop'ta 3. masaüstü; monitörlü kurulumda Dell'in 1. sırasına taşınır.
        var d = named([("builtin", 3, "Nova")])
        d.moveDesktopAcross(from: "builtin", desktop: 3, to: "external", at: 1, toCount: 2, mode: D)
        #expect(names(d, D) == ["external": ["1": "Nova"]])
        #expect(names(d, U) == ["builtin": ["3": "Nova"]])
    }

    @Test func reorderingMovesNamesOnThatScreenOnly() {
        var document = named([("external", 1, "A"), ("external", 3, "C"), ("builtin", 1, "L")])
        document.moveDesktop(on: "external", from: 3, to: 1, count: 3, mode: D)
        #expect(names(document)["external"] == ["1": "C", "2": "A"])
        #expect(names(document)["builtin"] == ["1": "L"])
    }

    @Test func removingDropsNameAndShiftsLaterOnes() {
        var document = named([("external", 1, "A"), ("external", 2, "B"), ("external", 4, "D")])
        document.removeDesktop(on: "external", desktop: 2, mode: D)
        #expect(names(document)["external"] == ["1": "A", "3": "D"])
    }

    @Test func movingAcrossScreensCarriesTheName() {
        var document = named([("external", 2, "Nova"), ("builtin", 1, "Mail"), ("external", 3, "X")])
        document.moveDesktopAcross(from: "external", desktop: 2, to: "builtin", at: 1,
                                   toCount: 1, mode: D)
        #expect(names(document)["builtin"] == ["1": "Nova", "2": "Mail"])
        #expect(names(document)["external"] == ["2": "X"])
        // Laptop kurulumundaki "Mail" yerinde kalır.
        #expect(names(document, U)["builtin"] == ["1": "Mail"])
    }

    @Test func roundTripsThroughJSONAndMigratesOldFiles() throws {
        let document = named([("external", 5, "Nova Project")])
        let decoded = try JSONDecoder().decode(Document.self, from: JSONEncoder().encode(document))
        #expect(decoded.desktopName(screen: "external", desktop: 5, mode: D) == "Nova Project")
        let plain = String(decoding: try JSONEncoder().encode(Document()), as: UTF8.self)
        #expect(!plain.contains("desktopNames"))
        // Eski biçim: anahtar yalnız ekran.
        var raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Document())) as! [String: Any]
        raw["desktopNames"] = ["builtin": ["2": "Laptop"], "external": ["1": "Dell"]]
        let old = try JSONDecoder().decode(Document.self, from: JSONSerialization.data(withJSONObject: raw))
        #expect(old.desktopName(screen: "builtin", desktop: 2, mode: U) == "Laptop")
        #expect(old.desktopName(screen: "builtin", desktop: 2, mode: D) == "Laptop")
        #expect(old.desktopName(screen: "external", desktop: 1, mode: D) == "Dell")
        #expect(old.desktopName(screen: "external", desktop: 1, mode: U) == nil)
    }

    @Test func urlCommandParses() {
        #expect(URLCommand.parse(URL(string: "deskmap://desktop-name/External/5?name=Nova%20Beam")!)
                == .nameDesktop(screen: "external", desktop: 5, name: "Nova Beam"))
        #expect(URLCommand.parse(URL(string: "deskmap://desktop-name/external/5")!)
                == .nameDesktop(screen: "external", desktop: 5, name: ""))
        #expect(URLCommand.parse(URL(string: "deskmap://desktop-name/external/0?name=x")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://desktop-name/external?name=x")!) == nil)
    }
}

/// Adların gerçek masaüstü kimliğini izlemesi (Mission Control), yalnız
/// etkin kurulumda.
struct DesktopNameReconcileTests {

    private func document(_ entries: [(String, Int, String, UInt64?)], mode: Mode = .docked) -> Document {
        var d = Document()
        for (screen, desktop, name, space) in entries {
            d.setDesktopName(name, screen: screen, desktop: desktop, mode: mode, space: space)
        }
        return d
    }

    @Test func followsReorderInMissionControl() {
        var d = document([("external", 2, "Nova", 202), ("external", 3, "Orion", 303)])
        let changed = d.reconcileDesktopNames(spaces: ["external": [101, 303, 202]],
                                              seen: [101, 202, 303], mode: D)
        #expect(changed)
        #expect(names(d)["external"] == ["3": "Nova", "2": "Orion"])
        #expect(bound(d, "external") == ["3": 202, "2": 303])
    }

    @Test func followsMoveToAnotherDisplay() {
        var d = document([("external", 2, "Nova", 202)])
        d.reconcileDesktopNames(spaces: ["external": [101], "builtin": [1, 202]],
                                seen: [101, 202, 1], mode: D)
        #expect(names(d) == ["builtin": ["2": "Nova"]])
    }

    @Test func otherSetupIsUntouchedWhenMacOSShufflesDesktops() {
        // Monitör çıktı: macOS Dell masaüstülerini (202) laptop'un sonuna ekledi.
        // Laptop kurulumunun Nova'su 3. masaüstünde (kendi kimliği 3) kalır;
        // monitörlü kurulumun adı (Dell/2) da dokunulmadan bekler.
        var d = document([("builtin", 3, "Nova", 3)], mode: U)
        d.moveDesktopAcross(from: "builtin", desktop: 3, to: "external", at: 2, toCount: 2, mode: D)
        d.desktopNameSpaces["docked|external"] = ["2": 202]
        d.reconcileDesktopNames(spaces: ["builtin": [1, 2, 3, 4, 202]], seen: [1, 2, 3, 4, 202], mode: U)
        #expect(names(d, U) == ["builtin": ["3": "Nova"]])
        #expect(names(d, D) == ["external": ["2": "Nova"]])
    }

    @Test func dropsNameOfDesktopDeletedInMissionControl() {
        var d = document([("external", 2, "Nova", 202), ("external", 3, "Orion", 303)])
        d.reconcileDesktopNames(spaces: ["external": [101, 303]], seen: [101, 202, 303], mode: D)
        #expect(names(d)["external"] == ["2": "Orion"])
    }

    @Test func unseenSpaceKeepsNumberAndRebinds() {
        var d = document([("external", 2, "Nova", 999)])
        d.reconcileDesktopNames(spaces: ["external": [11, 22, 33]], seen: [], mode: D)
        #expect(names(d)["external"] == ["2": "Nova"])
        #expect(bound(d, "external") == ["2": 22])
    }

    @Test func unboundNameBindsByNumberAndDisconnectedScreenIsUntouched() {
        var d = document([("external", 2, "Nova", nil), ("external-2", 1, "Yan", 77)])
        d.reconcileDesktopNames(spaces: ["external": [11, 22]], seen: [11, 22], mode: D)
        #expect(bound(d, "external") == ["2": 22])
        #expect(names(d)["external-2"] == ["1": "Yan"])
        #expect(bound(d, "external-2") == ["1": 77])
    }

    @Test func noChangeReturnsFalse() {
        var d = document([("external", 2, "Nova", 22)])
        let changed = d.reconcileDesktopNames(spaces: ["external": [11, 22]], seen: [11, 22], mode: D)
        #expect(!changed)
    }

    @Test func deskmapReorderDropsBindingSoNameStaysWithNumber() {
        var d = document([("external", 1, "A", 11)])
        d.moveDesktop(on: "external", from: 1, to: 2, count: 2, mode: D)
        #expect(names(d)["external"] == ["2": "A"])
        d.reconcileDesktopNames(spaces: ["external": [11, 22]], seen: [11, 22], mode: D)
        #expect(names(d)["external"] == ["2": "A"])
        #expect(bound(d, "external") == ["2": 22])
    }
}

/// Deskmap'in kendi masaüstü işlemlerinde adların ve pinlerin tutarlılığı.
struct DesktopNameDeskmapOpsTests {

    @Test func executingPendingRemovalDoesNotShiftNamesTwice() {
        var d = Document()
        d.setDesktopName("A", screen: "builtin", desktop: 1, mode: U)
        d.setDesktopName("C", screen: "builtin", desktop: 3, mode: U)
        d.removeDesktopLater(on: "builtin", desktop: 2, mode: .undocked, existing: true, space: nil)
        #expect(names(d, U)["builtin"] == ["1": "A", "2": "C"])
        d.removeDesktop(on: "builtin", desktop: 2, modes: [.docked], shiftNames: false)
        #expect(names(d, U)["builtin"] == ["1": "A", "2": "C"])
    }

    @Test func reorderShiftsPinsInEveryProfile() {
        var d = Document()
        var rule = Rule(appName: "Code", bundleID: "com.microsoft.VSCode", tokens: [])
        rule.docked = Destination(screen: "external", desktop: 1)
        d.rules = [rule]
        d.addProfile(named: "B", copyingCurrent: true)
        d.moveDesktop(on: "external", from: 1, to: 3, count: 3, mode: .docked)
        for profile in d.profiles {
            let rules = profile.id == d.activeProfileID ? d.rules : profile.rules
            #expect(rules.first?.docked?.desktop == 3, "profile \(profile.name)")
        }
    }
}

/// Kurulum değişiminde (monitör tak/çıkar) adlı masaüstündeki pencerelerin
/// aynı adlı masaüstüne taşınması.
struct NamedDesktopFollowTests {

    private func window(_ id: CGWindowID, _ screen: String, _ desktop: Int,
                        title: String = "t") -> Router.WindowSnapshot {
        Router.WindowSnapshot(id: id, pid: 1, appName: "A", bundleID: "a", title: title,
                              placement: Router.Placement(screen: screen, desktop: desktop),
                              frame: nil, isMinimized: false)
    }

    @Test func monitorOutBringsWindowsBackToTheLaptopPlace() {
        // Monitörlü kurulumda Nova = Dell/1, laptop kurulumunda Nova = laptop/3.
        let moves = Router.namedDesktopMoves(
            windows: [window(1, "external", 1), window(2, "external", 1), window(3, "external", 2),
                      window(4, "builtin", 2)],
            from: ["external": ["1": "Nova"]], to: ["builtin": ["3": "Nova"]],
            desktopCounts: ["builtin": 6]) { _ in false }
        #expect(moves.map(\.window) == [1, 2])
        #expect(moves.allSatisfy { $0.placement == Router.Placement(screen: "builtin", desktop: 3) })
    }

    @Test func pinnedWindowsMissingTargetsAndAmbiguousNamesAreSkipped() {
        let windows = [window(1, "external", 1), window(2, "external", 1), window(3, "external", 2)]
        let pinned = Router.namedDesktopMoves(
            windows: windows, from: ["external": ["1": "Nova"]], to: ["builtin": ["3": "Nova"]],
            desktopCounts: ["builtin": 6]) { $0.id == 2 }
        #expect(pinned.map(\.window) == [1])
        let missing = Router.namedDesktopMoves(
            windows: windows, from: ["external": ["1": "Nova"]], to: ["builtin": ["9": "Nova"]],
            desktopCounts: ["builtin": 6]) { _ in false }
        #expect(missing.isEmpty)
        let twice = Router.namedDesktopMoves(
            windows: windows, from: ["external": ["1": "Nova"]],
            to: ["builtin": ["3": "Nova", "4": "nova"]], desktopCounts: ["builtin": 6]) { _ in false }
        #expect(twice.isEmpty)
    }

    @Test func laptopDesktopsThatStayPutAreNotMoved() {
        let moves = Router.namedDesktopMoves(
            windows: [window(1, "builtin", 3)], from: ["builtin": ["3": "Nova"]],
            to: ["builtin": ["3": "Nova"]], desktopCounts: ["builtin": 6]) { _ in false }
        #expect(moves.isEmpty)
    }
}
