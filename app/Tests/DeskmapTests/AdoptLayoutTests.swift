import Foundation
import Testing
@testable import Deskmap

/// "Öbür kurulumdakini kullan": iki kurulumu aynı yerde (aynı ekran ve
/// masaüstü) olan kuralda düzenin bir kez öbür kuruluma kopyalanması
/// (`Rule.adoptLayout`, `Store.adoptLayout`, `deskmap://rule-copy-layout`).
struct AdoptLayoutTests {

    private func rule(docked: Destination?, undocked: Destination?,
                      dockedNext: [Destination] = []) -> Rule {
        Rule(id: "r", appName: "Safari", bundleID: "com.apple.Safari", tokens: [],
             docked: docked, undocked: undocked, dockedNext: dockedNext)
    }

    private let laptopLeft = Destination(screen: "builtin", desktop: 2, layout: .leftHalf)
    private let laptopRight = Destination(screen: "builtin", desktop: 2, layout: .rightHalf)

    // MARK: Aynı yer

    @Test func samePlaceByIndex() {
        #expect(laptopLeft.isSamePlace(as: laptopRight))
        #expect(!laptopLeft.isSamePlace(as: Destination(screen: "builtin", desktop: 3)))
        #expect(!laptopLeft.isSamePlace(as: Destination(screen: "external", desktop: 2)))
    }

    /// Ad hedefi adla karşılaştırılır (önbellekteki numara önemsiz), ekran
    /// yine aynı olmalı.
    @Test func samePlaceByName() {
        let a = Destination(screen: "builtin", desktop: 1, nameID: "N1")
        #expect(a.isSamePlace(as: Destination(screen: "builtin", desktop: 4, nameID: "N1")))
        #expect(!a.isSamePlace(as: Destination(screen: "builtin", desktop: 1, nameID: "N2")))
        #expect(!a.isSamePlace(as: Destination(screen: "external", desktop: 1, nameID: "N1")))
    }

    /// Biri ada biri numaraya bakıyorsa, numaralar tutsa da aynı yer değil.
    @Test func mixedNameAndIndexIsNotSamePlace() {
        let named = Destination(screen: "builtin", desktop: 2, nameID: "N1")
        #expect(!named.isSamePlace(as: laptopLeft))
        #expect(!laptopLeft.isSamePlace(as: named))
    }

    // MARK: Düzen farkı

    @Test func layoutsDifferOnlyWhenTheyPlaceDifferently() {
        #expect(WindowLayout.leftHalf.placesLike(.leftHalf))
        #expect(!WindowLayout.leftHalf.placesLike(.rightHalf))
        // İki "yalnız masaüstü": oranlar uygulanmaz, aynı.
        var onlyA = WindowLayout.leftHalf; onlyA.desktopOnly = true
        #expect(onlyA.placesLike(.anyFrame))
        #expect(!WindowLayout.anyFrame.placesLike(.full))
        // Sabit boyut: yalnız `fixed`; oranlar eski sürüm yedeği.
        let size = WindowLayout.FixedSize(width: 800, height: 600, anchor: .center)
        let fixedA = WindowLayout(fixed: size, screenSize: CGSize(width: 1000, height: 800))
        let fixedB = WindowLayout(fixed: size)
        #expect(fixedA != fixedB)
        #expect(fixedA.placesLike(fixedB))
        #expect(!fixedA.placesLike(WindowLayout(fixed: .init(width: 800, height: 600, anchor: .left))))
        #expect(!fixedB.placesLike(.full))
    }

    /// Oranlı düzenler "aynı alan" toleransıyla: son bitlerde ayrılan aynı
    /// yarım aynı yerleşimdir, düğme çıkmaz; tolerans dışı fark yine farktır.
    @Test func proportionalLayoutsUseTheSameAreaTolerance() {
        let noisy = WindowLayout(x: 0.50001, y: 0, w: 0.49999, h: 1)
        #expect(WindowLayout.rightHalf.placesLike(noisy))
        #expect(!WindowLayout.rightHalf.placesLike(WindowLayout(x: 0.51, y: 0, w: 0.49, h: 1)))
        let r = rule(docked: Destination(screen: "builtin", desktop: 2, layout: noisy),
                     undocked: laptopRight)
        #expect(!r.layoutDiffersAcrossSetups)
    }

    @Test func conditionNeedsSamePlaceAndDifferentLayout() {
        #expect(rule(docked: laptopRight, undocked: laptopLeft).layoutDiffersAcrossSetups)
        #expect(!rule(docked: laptopLeft, undocked: laptopLeft).layoutDiffersAcrossSetups)
        #expect(!rule(docked: Destination(screen: "external", desktop: 2, layout: .rightHalf),
                      undocked: laptopLeft).layoutDiffersAcrossSetups)
        #expect(!rule(docked: laptopRight, undocked: nil).layoutDiffersAcrossSetups)
        #expect(!rule(docked: nil, undocked: laptopLeft).layoutDiffersAcrossSetups)
    }

    /// Monitörlü planda yalnız ilk yer sayılır (panelin düzenlediği yer).
    @Test func onlyTheFirstDockedPlaceCounts() {
        let external = Destination(screen: "external", desktop: 1, layout: .full)
        let r = rule(docked: external, undocked: laptopLeft, dockedNext: [laptopRight])
        #expect(r.sharedPlace == nil)
        #expect(!r.layoutDiffersAcrossSetups)
    }

    // MARK: Kopya

    @Test func copiesBothDirectionsKeepingTheTarget() {
        let named = Destination(screen: "builtin", desktop: 2, layout: .leftHalf, nameID: "N1")
        var r = rule(docked: Destination(screen: "builtin", desktop: 5, layout: .rightHalf,
                                         nameID: "N1"),
                     undocked: named)
        let copied1 = r.adoptLayout(from: .undocked)
        #expect(copied1)
        #expect(r.docked == Destination(screen: "builtin", desktop: 5, layout: .leftHalf, nameID: "N1"))
        #expect(r.undocked == named)

        var back = rule(docked: laptopRight, undocked: laptopLeft)
        let copied2 = back.adoptLayout(from: .docked)
        #expect(copied2)
        #expect(back.undocked == laptopRight)
        #expect(back.docked == laptopRight)
        // İkinci kez: zaten aynı, dokunulmaz.
        let copied3 = back.adoptLayout(from: .docked)
        #expect(!copied3)
    }

    @Test func copyKeepsTheRestOfTheDockedList() {
        let lg = Destination(screen: "external-2", desktop: 1, layout: .full)
        var r = rule(docked: laptopRight, undocked: laptopLeft, dockedNext: [lg])
        let copied4 = r.adoptLayout(from: .undocked)
        #expect(copied4)
        #expect(r.places(.docked) == [laptopLeft, lg])
    }

    @Test func noCopyWhenNotSamePlace() {
        var r = rule(docked: Destination(screen: "external", desktop: 2, layout: .rightHalf),
                     undocked: laptopLeft)
        let before = r
        let copied5 = r.adoptLayout(from: .undocked)
        #expect(!copied5)
        #expect(r == before)
    }

    // MARK: Store: geri alma, tek seferlik

    @MainActor private func store(_ r: Rule) -> Store {
        var document = Document()
        document.rules = [r]
        return Store(demo: document)
    }

    @MainActor @Test func storeCopyIsUndoableAndOneShot() {
        let s = store(rule(docked: laptopRight, undocked: laptopLeft))
        #expect(s.adoptLayout(for: "r", from: .docked) == .copied)
        #expect(s.rule("r")?.undocked?.layout == .rightHalf)
        #expect(s.history.undoEntry?.label == "Layout copied from the other plan")

        // Bağ yok: sonradan monitörlü planı değiştirmek laptop planına geçmez.
        #expect(s.saveLayout(.center, for: "r", mode: .docked))
        #expect(s.rule("r")?.docked?.layout == .center)
        #expect(s.rule("r")?.undocked?.layout == .rightHalf)

        s.undo()
        s.undo()
        #expect(s.rule("r")?.undocked == laptopLeft)
        #expect(s.rule("r")?.docked == laptopRight)
    }

    @MainActor @Test func storeResultsForEveryCase() {
        let equal = store(rule(docked: laptopLeft, undocked: laptopLeft))
        #expect(equal.adoptLayout(for: "r", from: .undocked) == .alreadyEqual)
        #expect(!equal.history.canUndo)

        let apart = store(rule(docked: Destination(screen: "external", desktop: 2), undocked: laptopLeft))
        #expect(apart.adoptLayout(for: "r", from: .docked) == .notSamePlace)
        #expect(apart.adoptLayout(for: "missing", from: .docked) == .ruleNotFound)
        #expect(!apart.history.canUndo)

        // Tek planlı kural: "aynı yerde değil" değil, "plan yok".
        let single = store(rule(docked: nil, undocked: laptopLeft))
        #expect(single.adoptLayout(for: "r", from: .undocked) == .missingPlan)
        #expect(single.adoptLayout(for: "r", from: .docked) == .missingPlan)
        #expect(!single.history.canUndo)
    }

    // MARK: URL komutu

    @Test func parsesTheURLCommand() {
        #expect(URLCommand.parse(URL(string: "deskmap://rule-copy-layout/R1?from=docked")!)
                == .copyLayout(rule: "R1", from: .docked))
        #expect(URLCommand.parse(URL(string: "deskmap://rule-copy-layout/R1?from=Undocked&req=5")!)
                == .copyLayout(rule: "R1", from: .undocked))
        #expect(URLCommand.parse(URL(string: "deskmap://rule-copy-layout/R1")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://rule-copy-layout/R1?from=both")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://rule-copy-layout?from=docked")!) == nil)
    }

    @Test func urlCommandErrors() {
        #expect(URLCommands.copyLayoutError(.copied, ruleID: "R1") == nil)
        #expect(URLCommands.copyLayoutError(.alreadyEqual, ruleID: "R1") == nil)
        #expect(URLCommands.copyLayoutError(.ruleNotFound, ruleID: "R1") == "Rule not found: R1")
        #expect(URLCommands.copyLayoutError(.notSamePlace, ruleID: "R1")?.contains("R1") == true)
        #expect(URLCommands.copyLayoutError(.missingPlan, ruleID: "R1")
                == "This rule needs a target in both plans: R1")
    }
}
