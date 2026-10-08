import Foundation
import Testing
@testable import Deskmap

/// Masaüstü adları: verme/silme, masaüstü taşınınca ve silinince kayma,
/// dosyaya yazılıp okunma, URL komutu.
struct DesktopNameTests {

    private func named(_ pairs: [(String, Int, String)]) -> Document {
        var document = Document()
        for (screen, desktop, name) in pairs {
            document.setDesktopName(name, screen: screen, desktop: desktop)
        }
        return document
    }

    @Test func setTrimsAndEmptyRemoves() {
        var document = named([("external", 5, "  Nova  ")])
        #expect(document.desktopName(screen: "external", desktop: 5) == "Nova")
        document.setDesktopName("   ", screen: "external", desktop: 5)
        #expect(document.desktopName(screen: "external", desktop: 5) == nil)
        #expect(document.desktopNames.isEmpty)
    }

    @Test func reorderingMovesNamesOnThatScreenOnly() {
        var document = named([("external", 1, "A"), ("external", 3, "C"), ("builtin", 1, "L")])
        document.moveDesktop(on: "external", from: 3, to: 1, count: 3, mode: .docked)
        #expect(document.desktopName(screen: "external", desktop: 1) == "C")
        #expect(document.desktopName(screen: "external", desktop: 2) == "A")
        #expect(document.desktopName(screen: "external", desktop: 3) == nil)
        #expect(document.desktopName(screen: "builtin", desktop: 1) == "L")
    }

    @Test func removingDropsNameAndShiftsLaterOnes() {
        var document = named([("external", 1, "A"), ("external", 2, "B"), ("external", 4, "D")])
        document.removeDesktop(on: "external", desktop: 2, mode: .docked)
        #expect(document.desktopNames["external"] == ["1": "A", "3": "D"])
    }

    @Test func movingAcrossScreensCarriesTheName() {
        var document = named([("external", 2, "Nova"), ("builtin", 1, "Mail"), ("external", 3, "X")])
        document.moveDesktopAcross(from: "external", desktop: 2, to: "builtin", at: 1,
                                   toCount: 1, mode: .docked)
        #expect(document.desktopNames["builtin"] == ["1": "Nova", "2": "Mail"])
        #expect(document.desktopNames["external"] == ["2": "X"])
    }

    @Test func roundTripsThroughJSON() throws {
        let document = named([("external", 5, "Nova Project")])
        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(Document.self, from: data)
        #expect(decoded.desktopName(screen: "external", desktop: 5) == "Nova Project")
        // Ad yoksa alan hiç yazılmaz.
        let plain = String(decoding: try JSONEncoder().encode(Document()), as: UTF8.self)
        #expect(!plain.contains("desktopNames"))
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

/// Adların gerçek masaüstü kimliğini izlemesi (Mission Control'de yapılan
/// değişiklikler).
struct DesktopNameReconcileTests {

    private func document(_ entries: [(String, Int, String, UInt64?)]) -> Document {
        var d = Document()
        for (screen, desktop, name, space) in entries {
            d.setDesktopName(name, screen: screen, desktop: desktop, space: space)
        }
        return d
    }

    @Test func followsReorderInMissionControl() {
        var d = document([("external", 2, "Nova", 202), ("external", 3, "Orion", 303)])
        // Mission Control'de 2. masaüstü sona sürüklendi: 101 303 202
        let changed = d.reconcileDesktopNames(spaces: ["external": [101, 303, 202]],
                                              seen: [101, 202, 303])
        #expect(changed)
        #expect(d.desktopNames["external"] == ["3": "Nova", "2": "Orion"])
        #expect(d.desktopNameSpaces["external"] == ["3": 202, "2": 303])
    }

    @Test func followsMoveToAnotherDisplay() {
        var d = document([("external", 2, "Nova", 202)])
        d.reconcileDesktopNames(spaces: ["external": [101], "builtin": [1, 202]],
                                seen: [101, 202, 1])
        #expect(d.desktopNames == ["builtin": ["2": "Nova"]])
    }

    @Test func dropsNameOfDesktopDeletedInMissionControl() {
        var d = document([("external", 2, "Nova", 202), ("external", 3, "Orion", 303)])
        d.reconcileDesktopNames(spaces: ["external": [101, 303]], seen: [101, 202, 303])
        #expect(d.desktopNames["external"] == ["2": "Orion"])
    }

    @Test func unseenSpaceKeepsNumberAndRebinds() {
        // Yeniden başlatma: eski kimlikler bu oturumda hiç görülmedi.
        var d = document([("external", 2, "Nova", 999)])
        d.reconcileDesktopNames(spaces: ["external": [11, 22, 33]], seen: [])
        #expect(d.desktopNames["external"] == ["2": "Nova"])
        #expect(d.desktopNameSpaces["external"] == ["2": 22])
    }

    @Test func unboundNameBindsByNumberAndDisconnectedScreenIsUntouched() {
        var d = document([("external", 2, "Nova", nil), ("external-2", 1, "Yan", 77)])
        d.reconcileDesktopNames(spaces: ["external": [11, 22]], seen: [11, 22])
        #expect(d.desktopNameSpaces["external"] == ["2": 22])
        #expect(d.desktopNames["external-2"] == ["1": "Yan"])
        #expect(d.desktopNameSpaces["external-2"] == ["1": 77])
    }

    @Test func noChangeReturnsFalse() {
        var d = document([("external", 2, "Nova", 22)])
        let changed = d.reconcileDesktopNames(spaces: ["external": [11, 22]], seen: [11, 22])
        #expect(!changed)
    }

    @Test func deskmapReorderDropsBindingSoNameStaysWithNumber() {
        // Deskmap sırayı pencereleri taşıyarak değiştirir: ad yeni numarada
        // kalmalı, eski kimliğine geri dönmemeli.
        var d = document([("external", 1, "A", 11)])
        d.moveDesktop(on: "external", from: 1, to: 2, count: 2, mode: .docked)
        #expect(d.desktopNames["external"] == ["2": "A"])
        d.reconcileDesktopNames(spaces: ["external": [11, 22]], seen: [11, 22])
        #expect(d.desktopNames["external"] == ["2": "A"])
        #expect(d.desktopNameSpaces["external"] == ["2": 22])
    }
}
